// Copyright (c) Microsoft Corporation. All rights reserved.

#nullable enable

using System;
using System.Collections.Generic;
using System.Security.Claims;
using System.Text.Encodings.Web;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace Sample.Authentication;

/// <summary>
/// Validates a credential presented on an incoming request.
/// </summary>
/// <remarks>
/// This stands in for whatever the Katana handler called into: a user store, a token
/// introspection client, a database context. Register the real implementation with any
/// lifetime, including scoped -- the handler receives it through its constructor, so a
/// scoped registration is resolved once per request.
/// </remarks>
public interface ISampleCredentialValidator
{
    /// <summary>
    /// Validates <paramref name="credential"/> and returns the claims it carries, or
    /// <see langword="null"/> when the credential is present but not valid.
    /// </summary>
    Task<IReadOnlyList<Claim>?> ValidateAsync(string credential, CancellationToken cancellationToken);
}

/// <summary>
/// Options for the sample scheme. Replaces the Katana options type that derived from
/// <c>Microsoft.Owin.Security.AuthenticationOptions</c>.
/// </summary>
/// <remarks>
/// The Katana base class carried <c>AuthenticationType</c> and <c>AuthenticationMode</c>.
/// Neither has a property here: the scheme name is supplied to <c>AddScheme</c>, and
/// <c>AuthenticationMode</c> has no equivalent at all -- see step 7 of the skill.
/// </remarks>
public class SampleAuthenticationOptions : AuthenticationSchemeOptions
{
    /// <summary>Gets or sets the request header carrying the credential.</summary>
    public string HeaderName { get; set; } = "X-Sample-Credential";

    /// <summary>Gets or sets the realm reported on a challenge.</summary>
    public string Realm { get; set; } = "sample";

    /// <inheritdoc />
    public override void Validate()
    {
        base.Validate();

        if (string.IsNullOrWhiteSpace(HeaderName))
        {
            throw new InvalidOperationException($"{nameof(HeaderName)} must be a non-empty header name.");
        }

        // The realm is written into a response header verbatim, so reject the characters
        // that would let it break out of the quoted-string it is placed in.
        if (string.IsNullOrWhiteSpace(Realm) || Realm.IndexOfAny(['"', '\r', '\n']) >= 0)
        {
            throw new InvalidOperationException($"{nameof(Realm)} must be non-empty and must not contain quotes or line breaks.");
        }
    }
}

/// <summary>
/// Authenticates requests that carry a credential in a configured header.
/// </summary>
/// <remarks>
/// This sample is authenticate-only, which is why it derives from
/// <see cref="AuthenticationHandler{TOptions}"/>. A Katana handler that overrode
/// <c>ApplyResponseGrantAsync</c> to issue or clear its own credential must derive from
/// <c>SignInAuthenticationHandler</c> or <c>SignOutAuthenticationHandler</c> instead;
/// <c>HandleSignInAsync</c> and <c>HandleSignOutAsync</c> do not exist on this base class.
/// </remarks>
public class SampleAuthenticationHandler : AuthenticationHandler<SampleAuthenticationOptions>
{
    private readonly ISampleCredentialValidator _validator;

    /// <summary>
    /// Initializes a new instance of the <see cref="SampleAuthenticationHandler"/> class.
    /// </summary>
    /// <remarks>
    /// This is the three-argument base constructor. The four-argument overload taking
    /// <c>ISystemClock</c> is obsolete; a handler that needs the current time reads
    /// <c>TimeProvider</c> from <see cref="AuthenticationSchemeOptions"/>.
    ///
    /// Runtime collaborators belong here, not on the options object. Options and their
    /// configurators are singletons, so a service stashed on the options object becomes a
    /// captive dependency. The handler is registered transient and activated from
    /// <c>HttpContext.RequestServices</c>, so constructor parameters may be scoped.
    /// </remarks>
    public SampleAuthenticationHandler(
        IOptionsMonitor<SampleAuthenticationOptions> options,
        ILoggerFactory logger,
        UrlEncoder encoder,
        ISampleCredentialValidator validator)
        : base(options, logger, encoder)
    {
        _validator = validator ?? throw new ArgumentNullException(nameof(validator));
    }

    /// <summary>
    /// Replaces the Katana <c>AuthenticateCoreAsync</c> override.
    /// </summary>
    /// <remarks>
    /// Katana returned <see langword="null"/> for both "no credential" and "bad credential".
    /// ASP.NET Core separates them, and the distinction is load-bearing: <c>NoResult</c>
    /// leaves the request anonymous so another scheme or the challenge path can act, while
    /// <c>Fail</c> records a diagnosable reason for a credential that was presented and
    /// rejected.
    /// </remarks>
    protected override async Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        if (!Request.Headers.TryGetValue(Options.HeaderName, out var values))
        {
            return AuthenticateResult.NoResult();
        }

        var credential = values.ToString();
        if (string.IsNullOrWhiteSpace(credential))
        {
            return AuthenticateResult.NoResult();
        }

        var claims = await _validator.ValidateAsync(credential, Context.RequestAborted).ConfigureAwait(false);
        if (claims is null)
        {
            return AuthenticateResult.Fail("The presented credential is not valid.");
        }

        // The identity's authentication type and the ticket's scheme are both the scheme
        // name. Katana took the value from Options.AuthenticationType; here it arrives from
        // AddScheme, so one handler type can back several independently named schemes.
        var identity = new ClaimsIdentity(claims, Scheme.Name);
        var principal = new ClaimsPrincipal(identity);
        var ticket = new AuthenticationTicket(principal, new AuthenticationProperties(), Scheme.Name);

        return AuthenticateResult.Success(ticket);
    }

    /// <summary>
    /// Replaces the 401 half of the Katana <c>ApplyResponseChallengeAsync</c> override.
    /// </summary>
    /// <remarks>
    /// The first token of a <c>WWW-Authenticate</c> value is an HTTP <c>auth-scheme</c> token
    /// and may not contain spaces or separators. This sample reuses the ASP.NET Core scheme
    /// name, which is only safe because scheme names here are tokens; a scheme registered under
    /// a display-style name needs a separate challenge token on the options type.
    /// </remarks>
    protected override Task HandleChallengeAsync(AuthenticationProperties properties)
    {
        Response.StatusCode = StatusCodes.Status401Unauthorized;
        Response.Headers.WWWAuthenticate = $"{Scheme.Name} realm=\"{Options.Realm}\"";
        return Task.CompletedTask;
    }

    /// <summary>
    /// Replaces the 403 half of the Katana <c>ApplyResponseChallengeAsync</c> override.
    /// </summary>
    /// <remarks>
    /// Katana had no separate forbid path, so a handler that wrote 403 did so from inside its
    /// challenge override by inspecting the current user. Leaving this method unimplemented
    /// silently turns every authorization failure into the base 403 with none of the original
    /// response shape.
    /// </remarks>
    protected override Task HandleForbiddenAsync(AuthenticationProperties properties)
    {
        Response.StatusCode = StatusCodes.Status403Forbidden;
        return Task.CompletedTask;
    }
}

/// <summary>
/// Applies late-bound configuration to the sample scheme's options.
/// </summary>
/// <remarks>
/// This implements <see cref="IConfigureNamedOptions{TOptions}"/>, not the unnamed
/// <see cref="IConfigureOptions{TOptions}"/>. <c>AddScheme</c> stores options under the
/// scheme name and the handler reads them with <c>IOptionsMonitor.Get(Scheme.Name)</c>. An
/// unnamed configurator runs only for <c>Options.DefaultName</c>, so it would be registered,
/// resolved, and then silently skipped for every named scheme.
/// </remarks>
public class ConfigureSampleAuthenticationOptions : IConfigureNamedOptions<SampleAuthenticationOptions>
{
    private readonly IConfiguration _configuration;

    /// <summary>
    /// Initializes a new instance of the <see cref="ConfigureSampleAuthenticationOptions"/> class.
    /// </summary>
    public ConfigureSampleAuthenticationOptions(IConfiguration configuration)
    {
        _configuration = configuration ?? throw new ArgumentNullException(nameof(configuration));
    }

    /// <inheritdoc />
    public void Configure(string? name, SampleAuthenticationOptions options)
    {
        ArgumentNullException.ThrowIfNull(options);

        if (string.IsNullOrEmpty(name))
        {
            return;
        }

        var section = _configuration.GetSection($"Authentication:Schemes:{name}");
        if (!section.Exists())
        {
            return;
        }

        var headerName = section["HeaderName"];
        if (!string.IsNullOrWhiteSpace(headerName))
        {
            options.HeaderName = headerName;
        }

        var realm = section["Realm"];
        if (!string.IsNullOrWhiteSpace(realm))
        {
            options.Realm = realm;
        }
    }

    /// <inheritdoc />
    public void Configure(SampleAuthenticationOptions options) => Configure(Options.DefaultName, options);
}

/// <summary>
/// Registers the sample scheme. Replaces the Katana <c>IAppBuilder.UseSample</c> extension.
/// </summary>
public static class SampleAuthenticationExtensions
{
    /// <summary>
    /// Adds the sample scheme under <paramref name="authenticationScheme"/>.
    /// </summary>
    /// <remarks>
    /// The application must also register an <see cref="ISampleCredentialValidator"/>
    /// implementation. This method deliberately does not choose one, because the credential
    /// store is application state rather than part of the scheme.
    /// </remarks>
    public static AuthenticationBuilder AddSample(
        this AuthenticationBuilder builder,
        string authenticationScheme,
        string? displayName,
        Action<SampleAuthenticationOptions>? configureOptions)
    {
        ArgumentNullException.ThrowIfNull(builder);

        builder.Services.TryAddEnumerable(
            ServiceDescriptor.Singleton<IConfigureOptions<SampleAuthenticationOptions>, ConfigureSampleAuthenticationOptions>());

        return builder.AddScheme<SampleAuthenticationOptions, SampleAuthenticationHandler>(
            authenticationScheme,
            displayName,
            configureOptions);
    }

    /// <summary>
    /// Adds the sample scheme under <paramref name="authenticationScheme"/> with no display
    /// name and no inline configuration.
    /// </summary>
    public static AuthenticationBuilder AddSample(this AuthenticationBuilder builder, string authenticationScheme)
        => builder.AddSample(authenticationScheme, displayName: null, configureOptions: null);
}

/// <summary>
/// Hosts the logic a Katana handler ran from <c>ApplyResponseCoreAsync</c>.
/// </summary>
/// <remarks>
/// <para>
/// That method ran on <em>every</em> response, at header-send time, through Katana's
/// <c>OnSendingHeaders</c>. Two things follow, and both are load-bearing.
/// </para>
/// <para>
/// First, no ASP.NET Core handler override reproduces it, because each override fires on
/// exactly one outcome. Second, this middleware is registered <em>before</em>
/// <c>UseAuthentication()</c>, not after: a handler implementing
/// <c>IAuthenticationRequestHandler</c> can short-circuit the pipeline from inside the
/// authentication middleware, and anything registered after it never runs on those responses.
/// </para>
/// <para>
/// The work goes in an <see cref="HttpResponse.OnStarting(Func{Task})"/> callback rather than
/// straight-line code before <c>next</c>. The callback runs just before headers are sent, so it
/// observes the final status code and the authenticated user, and it survives a downstream
/// <c>Response.Clear()</c>. Registering the same callback from <c>HandleAuthenticateAsync</c> is
/// the trap this shape exists to avoid: the callback is only registered on the requests that
/// reach that override.
/// </para>
/// </remarks>
public static class SampleResponseMarkerExtensions
{
    /// <summary>
    /// The header stamped on every response.
    /// </summary>
    public const string MarkerHeaderName = "X-Sample-Auth-Scheme";

    /// <summary>
    /// Stamps <see cref="MarkerHeaderName"/> on every response, reproducing what the Katana
    /// handler did from <c>ApplyResponseCoreAsync</c>. Register this <em>before</em>
    /// <c>UseAuthentication()</c>.
    /// </summary>
    public static IApplicationBuilder UseSampleResponseMarker(
        this IApplicationBuilder app,
        string authenticationScheme)
    {
        ArgumentNullException.ThrowIfNull(app);
        ArgumentException.ThrowIfNullOrEmpty(authenticationScheme);

        return app.Use(async (context, next) =>
        {
            context.Response.OnStarting(() =>
            {
                context.Response.Headers[MarkerHeaderName] = authenticationScheme;
                return Task.CompletedTask;
            });

            await next(context).ConfigureAwait(false);
        });
    }
}
