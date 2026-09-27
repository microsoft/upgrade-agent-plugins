// Copyright (c) Microsoft Corporation. All rights reserved.

using System;
using System.Linq;
using System.Security.Claims;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Authorization.Policy;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Authorization;
using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.AspNetCore.Mvc.ViewFeatures;

namespace AuthorizationMigrationSample;

public sealed record ExistingRoleRequirement(string Role) : IAuthorizationRequirement;

public static class ExistingIdentity
{
    public static bool IsAuthenticated(AuthorizationHandlerContext context)
        => context.User.Identity?.IsAuthenticated == true;
}

public sealed class ExistingRoleHandler : AuthorizationHandler<ExistingRoleRequirement>
{
    protected override Task HandleRequirementAsync(
        AuthorizationHandlerContext context, ExistingRoleRequirement requirement)
    {
        if (ExistingIdentity.IsAuthenticated(context) && context.User.IsInRole(requirement.Role))
        {
            context.Succeed(requirement);
        }

        return Task.CompletedTask;
    }
}

public sealed record UiFlowContract(
    string RetiredLoginClaimType,
    string NudgeKey,
    string HomeAction,
    string HomeController,
    string HomeArea);

[AttributeUsage(AttributeTargets.Class | AttributeTargets.Method, AllowMultiple = true, Inherited = true)]
public sealed class UiAccessAttribute : TypeFilterAttribute
{
    public UiAccessAttribute(string policy, bool allowRetiredLogin = false)
        : base(typeof(UiAccessFilter))
    {
        Arguments = [policy, allowRetiredLogin];
    }
}

public sealed class UiAccessFilter(
    IAuthorizationPolicyProvider policies,
    IPolicyEvaluator evaluator,
    ITempDataDictionaryFactory tempDataFactory,
    UiFlowContract contract,
    string policy,
    bool allowRetiredLogin) : IAsyncAuthorizationFilter, IAsyncAlwaysRunResultFilter
{
    private AuthorizationTempData? _tempData;
    private AuthorizationFilterContext? _authorizationContext;

    public async Task OnAuthorizationAsync(AuthorizationFilterContext context)
    {
        _authorizationContext = context;
        AuthorizationResponseCache.Protect(context.HttpContext);
        var (resolvedPolicy, authentication) = await FilterPolicy.AuthenticateAsync(context, policies, evaluator, policy);
        var identity = context.HttpContext.User.Identity as ClaimsIdentity;
        var retiredLogin = identity?.IsAuthenticated == true
            && string.Equals(identity.FindFirst(contract.RetiredLoginClaimType)?.Value,
                "true", StringComparison.OrdinalIgnoreCase);
        var tempData = tempDataFactory.GetTempData(context.HttpContext);
        _tempData = AuthorizationTempData.ForRequest(context.HttpContext, tempData);

        if ((!allowRetiredLogin && retiredLogin) || tempData.ContainsKey(contract.NudgeKey))
        {
            context.Result = new RedirectToRouteResult(new
            {
                area = contract.HomeArea,
                controller = contract.HomeController,
                action = contract.HomeAction,
            });
        }

        // Legacy pre-base effects also ran on anonymous exemptions.
        if (!AnonymousAccess.IsAllowed(context))
        {
            var result = await evaluator.AuthorizeAsync(resolvedPolicy, authentication, context.HttpContext, context);
            if (!result.Succeeded)
            {
                // This example's legacy override challenged even an authenticated denial.
                context.Result = new ChallengeResult();
            }
        }
    }

    public async Task OnResultExecutionAsync(ResultExecutingContext context, ResultExecutionDelegate next)
    {
        // All authorization filters share this context, including one that denies later.
        // A resource/action short-circuit instead leaves its Result null; MVC owns that save.
        if (_authorizationContext?.Result is null || _tempData is null)
        {
            await next();
            return;
        }

        var response = context.HttpContext.Response;
        _tempData.RegisterSave(response, () => context.Result);
        bool completed = false;
        try
        {
            var executed = await next();
            completed = executed.Exception is null || executed.ExceptionHandled;
            // No-body results can finish before OnStarting fires and before session teardown.
            if (completed && !response.HasStarted)
            {
                _tempData.SaveOnce(executed.Result);
            }
        }
        finally
        {
            if (!completed)
            {
                _tempData.SuppressSave();
            }
        }
    }
}

public interface ICredentialWarningWriter
{
    Task WriteAsync(HttpContext context);
}

[AttributeUsage(AttributeTargets.Class | AttributeTargets.Method, AllowMultiple = true, Inherited = true)]
public sealed class ApiAccessAttribute : TypeFilterAttribute
{
    public ApiAccessAttribute(string policy, string challengeScheme)
        : base(typeof(ApiAccessFilter))
    {
        Arguments = [policy, challengeScheme];
    }
}

public sealed class ApiAccessFilter(
    IAuthorizationPolicyProvider policies,
    IPolicyEvaluator evaluator,
    ICredentialWarningWriter warnings,
    string policy,
    string challengeScheme) : IAsyncAuthorizationFilter
{
    public async Task OnAuthorizationAsync(AuthorizationFilterContext context)
    {
        AuthorizationResponseCache.Protect(context.HttpContext);
        var (resolvedPolicy, authentication) = await FilterPolicy.AuthenticateAsync(context, policies, evaluator, policy);
        await warnings.WriteAsync(context.HttpContext);

        if (AnonymousAccess.IsAllowed(context))
        {
            return;
        }

        var result = await evaluator.AuthorizeAsync(resolvedPolicy, authentication, context.HttpContext, context);
        if (!result.Succeeded)
        {
            context.Result = new ChallengeResult(challengeScheme);
        }
    }
}

internal static class AuthorizationResponseCache
{
    private static readonly object RegistrationKey = new();

    internal static void Protect(HttpContext context)
    {
        if (context.Items.ContainsKey(RegistrationKey))
        {
            return;
        }

        SetHeaders(context.Response);
        context.Response.OnStarting(() =>
        {
            // Reapply after result/action filters so public cache directives cannot win.
            SetHeaders(context.Response);
            return Task.CompletedTask;
        });
        context.Items.Add(RegistrationKey, true);
    }

    private static void SetHeaders(HttpResponse response)
    {
        response.Headers.CacheControl = "private, no-store, no-cache";
        response.Headers.Pragma = "no-cache";
        response.Headers.Expires = "Thu, 01 Jan 1970 00:00:00 GMT";
    }
}

internal static class FilterPolicy
{
    internal static async Task<(AuthorizationPolicy Policy, AuthenticateResult Authentication)> AuthenticateAsync(
        AuthorizationFilterContext context, IAuthorizationPolicyProvider policies, IPolicyEvaluator evaluator, string name)
    {
        var policy = await policies.GetPolicyAsync(name)
            ?? throw new InvalidOperationException($"Authorization policy '{name}' is not registered.");
        var authentication = await evaluator.AuthenticateAsync(policy, context.HttpContext);
        return (policy, authentication);
    }
}

internal sealed class AuthorizationTempData(ITempDataDictionary data)
{
    private static readonly object StateKey = new();
    private bool _saved;
    private bool _registered;
    private bool _suppressed;

    internal static AuthorizationTempData ForRequest(HttpContext context, ITempDataDictionary data)
    {
        if (context.Items.TryGetValue(StateKey, out var state))
        {
            return (AuthorizationTempData)state!;
        }

        var created = new AuthorizationTempData(data);
        context.Items.Add(StateKey, created);
        return created;
    }

    internal void RegisterSave(HttpResponse response, Func<IActionResult> result)
    {
        if (_registered)
        {
            return;
        }

        if (response.HasStarted)
        {
            throw new InvalidOperationException("Authorization TempData must be saved before the response starts.");
        }

        response.OnStarting(() =>
        {
            SaveOnce(result());
            return Task.CompletedTask;
        });
        _registered = true;
    }

    internal void SuppressSave() => _suppressed = true;

    internal void SaveOnce(IActionResult result)
    {
        if (_saved || _suppressed)
        {
            return;
        }

        if (result is IKeepTempDataResult)
        {
            data.Keep();
        }

        data.Save();
        _saved = true;
    }
}

internal static class AnonymousAccess
{
    internal static bool IsAllowed(AuthorizationFilterContext context)
        => context.HttpContext.GetEndpoint()?.Metadata.GetMetadata<IAllowAnonymous>() is not null
            || context.Filters.Any(filter => filter is IAllowAnonymousFilter);
}
