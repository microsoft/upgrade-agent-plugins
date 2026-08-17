// Copyright (c) Microsoft Corporation. All rights reserved.

using System;
using System.Diagnostics;
using System.Globalization;
using System.Security.Claims;
using System.Text;
using System.Threading.Tasks;
using Microsoft.AspNetCore.DataProtection;
using Microsoft.Owin;
using Microsoft.Owin.Security;
using Microsoft.Owin.Security.Cookies;
using Microsoft.Owin.Security.DataHandler;
using Microsoft.Owin.Security.DataProtection;
using Microsoft.Owin.Security.Interop;
using Owin;
using CoreDataProtectionProvider = Microsoft.AspNetCore.DataProtection.IDataProtectionProvider;
using ICookieManager = Microsoft.Owin.Infrastructure.ICookieManager;

namespace SharedCookieInterop
{
    public static class LegacyCookieTransition
    {
        public const string UpgradeMarker = ".shared-cookie-upgrade";

        private const string PendingMarkerValue = "pending";
        private const string CookieMiddlewarePurpose = "Microsoft.AspNetCore.Authentication.Cookies.CookieAuthenticationMiddleware";

        public static void Configure(
            IAppBuilder app,
            CoreDataProtectionProvider sharedDataProtectionProvider,
            CookieAuthenticationOptions options,
            CookieAuthenticationProvider provider,
            Action onLegacyCookieRead)
        {
            if (app is null)
            {
                throw new ArgumentNullException(nameof(app));
            }

            if (sharedDataProtectionProvider is null)
            {
                throw new ArgumentNullException(nameof(sharedDataProtectionProvider));
            }

            if (options is null)
            {
                throw new ArgumentNullException(nameof(options));
            }

            if (provider is null)
            {
                throw new ArgumentNullException(nameof(provider));
            }

            if (string.IsNullOrWhiteSpace(options.AuthenticationType))
            {
                throw new ArgumentException("Set an explicit authentication type that matches the ASP.NET Core scheme.", nameof(options));
            }

            if (string.IsNullOrWhiteSpace(options.CookieName))
            {
                throw new ArgumentException("Set the existing cookie name explicitly so active sessions remain discoverable.", nameof(options));
            }

            if (!(options.SessionStore is null))
            {
                throw new InvalidOperationException("Shared cookies cannot use an ITicketStore/SessionStore.");
            }

            if (app.GetDataProtectionProvider() is null)
            {
                throw new InvalidOperationException(
                    "Katana has no host data-protection provider. Verify Microsoft.Owin.Host.SystemWeb is active before creating the legacy protector.");
            }

            var newFormat = new AspNetTicketDataFormat(
                new DataProtectorShim(
                    sharedDataProtectionProvider.CreateProtector(
                        CookieMiddlewarePurpose,
                        options.AuthenticationType,
                        "v2")));

            var legacyFormat = new TicketDataFormat(
                app.CreateDataProtector(
                    typeof(CookieAuthenticationMiddleware).FullName,
                    options.AuthenticationType,
                    "v1"));

            options.TicketDataFormat = new LegacyCookieTransitionDataFormat(newFormat, legacyFormat);
            options.CookieManager = new TransitionChunkingCookieManager(
                options.CookieManager ?? new Microsoft.Owin.Host.SystemWeb.SystemWebCookieManager());

            var validateIdentity = provider.OnValidateIdentity;
            provider.OnValidateIdentity = context => ValidateAndRewriteAsync(
                context,
                validateIdentity,
                options.AuthenticationType,
                onLegacyCookieRead);
            options.Provider = provider;
        }

        private static async Task ValidateAndRewriteAsync(
            CookieValidateIdentityContext context,
            Func<CookieValidateIdentityContext, Task> validateIdentity,
            string authenticationType,
            Action onLegacyCookieRead)
        {
            if (!(validateIdentity is null))
            {
                await validateIdentity(context).ConfigureAwait(false);
            }

            string marker;
            if (!context.Properties.Dictionary.TryGetValue(UpgradeMarker, out marker)
                || !string.Equals(marker, PendingMarkerValue, StringComparison.Ordinal))
            {
                return;
            }

            RecordLegacyCookieRead(onLegacyCookieRead);
            if (context.Identity is null)
            {
                return;
            }

            var identity = EnsureAuthenticationType(context.Identity, authenticationType);
            if (!ReferenceEquals(identity, context.Identity))
            {
                context.ReplaceIdentity(identity);
            }

            context.Properties.Dictionary.Remove(UpgradeMarker);
            context.OwinContext.Authentication.SignIn(context.Properties, context.Identity);
        }

        private static ClaimsIdentity EnsureAuthenticationType(ClaimsIdentity identity, string authenticationType)
        {
            if (string.Equals(identity.AuthenticationType, authenticationType, StringComparison.Ordinal))
            {
                return identity;
            }

            var normalized = new ClaimsIdentity(
                identity.Claims,
                authenticationType,
                identity.NameClaimType,
                identity.RoleClaimType)
            {
                BootstrapContext = identity.BootstrapContext,
                Label = identity.Label,
            };

            if (!(identity.Actor is null))
            {
                normalized.Actor = identity.Actor;
            }

            return normalized;
        }

        private static void RecordLegacyCookieRead(Action onLegacyCookieRead)
        {
            if (onLegacyCookieRead is null)
            {
                return;
            }

            try
            {
                onLegacyCookieRead();
            }
            catch (Exception exception)
            {
                // Monitoring failures must not turn a valid legacy session into an authentication outage.
                Trace.TraceError("The legacy-cookie monitoring callback failed: {0}", exception);
            }
        }

        public sealed class TransitionChunkingCookieManager : ICookieManager
        {
            private const int DefaultChunkSize = 4050;
            // Fifty 4 KB chunks allow an oversized ~200 KB ticket while bounding work from an untrusted marker.
            private const int MaximumChunkCount = 50;
            private const string ChunkKeySuffix = "C";
            private const string CoreChunkCountPrefix = "chunks-";
            private const string LegacyChunkCountPrefix = "chunks:";

            private readonly ICookieManager _inner;

            public TransitionChunkingCookieManager()
                : this(new Microsoft.Owin.Infrastructure.CookieManager())
            {
            }

            public TransitionChunkingCookieManager(ICookieManager inner)
            {
                _inner = inner ?? throw new ArgumentNullException(nameof(inner));
                if (inner is TransitionChunkingCookieManager)
                {
                    throw new ArgumentException(
                        "This manager is already installed. Call LegacyCookieTransition.Configure once per options instance; "
                        + "a second call double-wraps the cookie manager and composes the validation callback onto itself.",
                        nameof(inner));
                }

                if (inner is Microsoft.Owin.Infrastructure.ChunkingCookieManager
                    || inner is Microsoft.Owin.Security.Interop.ChunkingCookieManager
                    || inner is Microsoft.Owin.Host.SystemWeb.SystemWebChunkingCookieManager)
                {
                    throw new ArgumentException(
                        "Pass a non-chunking cookie writer; this manager owns chunk parsing and cleanup.",
                        nameof(inner));
                }

                ChunkSize = DefaultChunkSize;
                AcceptLegacyChunks = true;
            }

            public bool AcceptLegacyChunks { get; set; }

            public int? ChunkSize { get; set; }

            public bool ThrowForPartialCookies { get; set; }

            public string GetRequestCookie(IOwinContext context, string key)
            {
                ValidateArguments(context, key);

                var marker = context.Request.Cookies[key];
                var chunksCount = ParseChunksCount(marker);
                if (chunksCount == 0)
                {
                    return _inner.GetRequestCookie(context, key);
                }

                var value = new StringBuilder();
                for (var chunkId = 1; chunkId <= chunksCount; chunkId++)
                {
                    var chunk = _inner.GetRequestCookie(
                        context,
                        key + ChunkKeySuffix + chunkId.ToString(CultureInfo.InvariantCulture));
                    if (string.IsNullOrEmpty(chunk))
                    {
                        if (ThrowForPartialCookies)
                        {
                            throw new FormatException(
                                string.Format(
                                    CultureInfo.CurrentCulture,
                                    "The chunked cookie is incomplete. Only {0} of the expected {1} chunks were found.",
                                    chunkId - 1,
                                    chunksCount));
                        }

                        return marker;
                    }

                    value.Append(chunk);
                }

                return value.ToString();
            }

            public void AppendResponseCookie(IOwinContext context, string key, string value, CookieOptions options)
            {
                ValidateArguments(context, key, options);

                value = value ?? string.Empty;
                var templateLength = GetCookieTemplateLength(key, options);
                if (!ChunkSize.HasValue || ChunkSize.Value > templateLength + value.Length)
                {
                    _inner.AppendResponseCookie(context, key, value, options);
                    return;
                }

                if (ChunkSize.Value < templateLength + 10)
                {
                    throw new InvalidOperationException("The cookie key and options leave no room for chunk data.");
                }

                var dataSizePerCookie = ChunkSize.Value - templateLength - 3;
                var cookieChunkCount = (int)Math.Ceiling(value.Length * 1.0 / dataSizePerCookie);
                if (cookieChunkCount > MaximumChunkCount)
                {
                    throw new InvalidOperationException(
                        "The cookie exceeds the supported maximum of "
                        + MaximumChunkCount.ToString(CultureInfo.InvariantCulture)
                        + " chunks.");
                }

                _inner.AppendResponseCookie(
                    context,
                    key,
                    CoreChunkCountPrefix + cookieChunkCount.ToString(CultureInfo.InvariantCulture),
                    options);

                var offset = 0;
                for (var chunkId = 1; chunkId <= cookieChunkCount; chunkId++)
                {
                    var length = Math.Min(dataSizePerCookie, value.Length - offset);
                    var segment = value.Substring(offset, length);
                    offset += length;
                    _inner.AppendResponseCookie(
                        context,
                        key + ChunkKeySuffix + chunkId.ToString(CultureInfo.InvariantCulture),
                        segment,
                        options);
                }
            }

            // Chunk cleanup is driven by the request's chunk marker, so a cookie that shrinks
            // from chunked to unchunked leaves its stale C1..Cn cookies behind until they
            // expire. This matches Microsoft.Owin.Security.Interop.ChunkingCookieManager
            // exactly; it is upstream behavior, not something this wrapper introduces.
            public void DeleteCookie(IOwinContext context, string key, CookieOptions options)
            {
                ValidateArguments(context, key, options);

                var chunksCount = ParseChunksCount(context.Request.Cookies[key]);
                _inner.DeleteCookie(context, key, options);
                for (var chunkId = 1; chunkId <= chunksCount; chunkId++)
                {
                    var chunkKey = key + ChunkKeySuffix + chunkId.ToString(CultureInfo.InvariantCulture);
                    if (string.IsNullOrEmpty(_inner.GetRequestCookie(context, chunkKey)))
                    {
                        break;
                    }

                    _inner.DeleteCookie(
                        context,
                        chunkKey,
                        options);
                }
            }

            private int ParseChunksCount(string value)
            {
                var prefix = CoreChunkCountPrefix;
                if (AcceptLegacyChunks
                    && !(value is null)
                    && value.StartsWith(LegacyChunkCountPrefix, StringComparison.Ordinal))
                {
                    prefix = LegacyChunkCountPrefix;
                }

                if (value is null || !value.StartsWith(prefix, StringComparison.Ordinal))
                {
                    return 0;
                }

                int chunksCount;
                return int.TryParse(
                    value.Substring(prefix.Length),
                    NumberStyles.None,
                    CultureInfo.InvariantCulture,
                    out chunksCount)
                    && chunksCount > 0
                    && chunksCount <= MaximumChunkCount
                    ? chunksCount
                    : 0;
            }

            private static int GetCookieTemplateLength(string key, CookieOptions options)
            {
                var length = key.Length + 1;
                if (!string.IsNullOrEmpty(options.Domain))
                {
                    length += "; domain=".Length + options.Domain.Length;
                }

                if (!string.IsNullOrEmpty(options.Path))
                {
                    length += "; path=".Length + options.Path.Length;
                }

                if (options.Expires.HasValue)
                {
                    length += "; expires=ddd, dd-MMM-yyyy HH:mm:ss GMT".Length;
                }

                if (options.Secure)
                {
                    length += "; secure".Length;
                }

                if (options.HttpOnly)
                {
                    length += "; HttpOnly".Length;
                }

                if (options.SameSite.HasValue)
                {
                    length += "; SameSite=".Length + options.SameSite.Value.ToString().Length;
                }

                return length;
            }

            private static void ValidateArguments(IOwinContext context, string key)
            {
                if (context is null)
                {
                    throw new ArgumentNullException(nameof(context));
                }

                if (key is null)
                {
                    throw new ArgumentNullException(nameof(key));
                }
            }

            private static void ValidateArguments(IOwinContext context, string key, CookieOptions options)
            {
                ValidateArguments(context, key);
                if (options is null)
                {
                    throw new ArgumentNullException(nameof(options));
                }
            }
        }

        public sealed class LegacyCookieTransitionDataFormat : ISecureDataFormat<AuthenticationTicket>
        {
            private readonly ISecureDataFormat<AuthenticationTicket> _newFormat;
            private readonly ISecureDataFormat<AuthenticationTicket> _legacyFormat;

            public LegacyCookieTransitionDataFormat(
                ISecureDataFormat<AuthenticationTicket> newFormat,
                ISecureDataFormat<AuthenticationTicket> legacyFormat)
            {
                _newFormat = newFormat ?? throw new ArgumentNullException(nameof(newFormat));
                _legacyFormat = legacyFormat ?? throw new ArgumentNullException(nameof(legacyFormat));
            }

            public string Protect(AuthenticationTicket data)
                => _newFormat.Protect(data);

            // The purpose-taking overloads exist only to satisfy ISecureDataFormat. Katana's
            // cookie middleware always calls the single-argument overloads, so these are
            // unreachable from the wiring this reference documents; they delegate to the same
            // path deliberately rather than deriving a second, divergent protector.
            public string Protect(AuthenticationTicket data, string purpose)
                => _newFormat.Protect(data);

            public AuthenticationTicket Unprotect(string protectedText)
            {
                // Katana returns null rather than propagating a decryption exception.
                var ticket = _newFormat.Unprotect(protectedText);
                return ticket ?? MarkForUpgrade(_legacyFormat.Unprotect(protectedText));
            }

            public AuthenticationTicket Unprotect(string protectedText, string purpose)
            {
                var ticket = _newFormat.Unprotect(protectedText);
                return ticket ?? MarkForUpgrade(_legacyFormat.Unprotect(protectedText));
            }

            private static AuthenticationTicket MarkForUpgrade(AuthenticationTicket ticket)
            {
                if (ticket is null)
                {
                    return null;
                }

                ticket.Properties.Dictionary[UpgradeMarker] = PendingMarkerValue;
                return ticket;
            }
        }
    }
}
