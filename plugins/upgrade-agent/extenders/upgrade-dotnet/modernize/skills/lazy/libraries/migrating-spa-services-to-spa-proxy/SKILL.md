---
name: migrating-spa-services-to-spa-proxy
description: >
  Migrates ASP.NET Core projects from the obsolete
  Microsoft.AspNetCore.SpaServices.Extensions to
  Microsoft.AspNetCore.SpaProxy for Angular and React SPAs.
  Use ONLY when Microsoft.AspNetCore.SpaServices.Extensions
  has been flagged as obsolete or deprecated and must be
  replaced — not for version-bump scenarios where
  SpaServices.Extensions is still supported.
metadata:
  discovery: lazy
  traits: .NET|CSharp|DotNetCore
---

# SpaServices to SpaProxy Migration

## Overview

Migrate ASP.NET Core projects from `Microsoft.AspNetCore.SpaServices.Extensions` to `Microsoft.AspNetCore.SpaProxy`. The backend no longer manages the SPA dev server inline via `UseSpa()`; instead, `SpaProxy` automatically launches the frontend dev server and proxies requests to it. This removes all SpaServices middleware from `Startup.cs` and moves configuration to the project file and hosting startup assembly.

Covers both **Angular** and **React** frontends. Steps are shared unless marked framework-specific.

## Workflow

```
Migration Progress:
- [ ] Step 1: Detect SpaServices usage and identify frontend framework
- [ ] Step 2: Update Startup.cs
- [ ] Step 3: Update the project file
- [ ] Step 4: Update launchSettings.json
- [ ] Step 5: Update package.json
- [ ] Step 6: Update angular.json (Angular only)
- [ ] Step 7: Add HTTPS and proxy configuration files
- [ ] Step 8: Build and verify
```

### Step 1: Detect SpaServices Usage

Scan the project for:
- Package references to `Microsoft.AspNetCore.SpaServices.Extensions`
- Calls to `AddSpaStaticFiles()`, `UseSpaStaticFiles()`, `UseSpa()`
- `spa.UseAngularCliServer()` (Angular) or `spa.UseReactDevelopmentServer()` (React)

Identify the frontend framework — Angular projects have `angular.json`, React projects have `react-scripts` in `package.json`. This determines which steps and files apply.

### Step 2: Update Startup.cs

Remove three blocks of SpaServices middleware. No replacement middleware is needed — `SpaProxy` activates via a hosting startup assembly.

**Remove `AddSpaStaticFiles()`:**
```csharp
// DELETE this entire block
services.AddSpaStaticFiles(configuration =>
{
    configuration.RootPath = "ClientApp/dist";
});
```

**Remove `UseSpaStaticFiles()`:**
```csharp
// DELETE this entire block
if (!env.IsDevelopment())
{
    app.UseSpaStaticFiles();
}
```

**Remove `UseSpa()` (Angular variant):**
```csharp
// DELETE this entire block
app.UseSpa(spa =>
{
    spa.Options.SourcePath = "ClientApp";

    if (env.IsDevelopment())
    {
        spa.UseAngularCliServer(npmScript: "start");
    }
});
```

**Remove `UseSpa()` (React variant):**
```csharp
// DELETE this entire block
app.UseSpa(spa =>
{
    spa.Options.SourcePath = "ClientApp";

    if (env.IsDevelopment())
    {
        spa.UseReactDevelopmentServer(npmScript: "start");
    }
});
```

**Add fallback route** inside `app.UseEndpoints(...)`:
```csharp
app.UseEndpoints(endpoints =>
{
    // ... existing endpoints ...
    endpoints.MapFallbackToFile("index.html");
});
```

### Step 3: Update the Project File

**Replace the package reference:**
```diff
-<PackageReference Include="Microsoft.AspNetCore.SpaServices.Extensions" Version="..." />
+<PackageReference Include="Microsoft.AspNetCore.SpaProxy" Version="..." />
```

**Add SpaProxy properties** (choose a frontend port that does not conflict with the backend port):
```xml
<PropertyGroup>
  <SpaProxyServerUrl>https://localhost:44416</SpaProxyServerUrl>
  <SpaProxyLaunchCommand>npm start</SpaProxyLaunchCommand>
</PropertyGroup>
```

**Update MSBuild targets** to ensure Node.js availability and publish the SPA output to `wwwroot`:

For **Angular** (output goes to `dist\` and `dist-server\`):
```xml
<Target Name="DebugEnsureNodeEnv" BeforeTargets="Build" Condition=" '$(Configuration)' == 'Debug' And !Exists('$(SpaRoot)node_modules') ">
  <Exec Command="node --version" ContinueOnError="true">
    <Output TaskParameter="ExitCode" PropertyName="ErrorCode" />
  </Exec>
  <Error Condition="'$(ErrorCode)' != '0'" Text="Node.js is required to build and run this project. To continue, please install Node.js from https://nodejs.org/, and then restart your command prompt or IDE." />
  <Message Importance="high" Text="Restoring dependencies using 'npm'. This may take several minutes..." />
  <Exec WorkingDirectory="$(SpaRoot)" Command="npm install" />
</Target>

<Target Name="PublishRunWebpack" AfterTargets="ComputeFilesToPublish">
  <Exec WorkingDirectory="$(SpaRoot)" Command="npm install" />
  <Exec WorkingDirectory="$(SpaRoot)" Command="npm run build -- --configuration production" />
  <ItemGroup>
    <DistFiles Include="$(SpaRoot)dist\**; $(SpaRoot)dist-server\**" />
    <ResolvedFileToPublish Include="@(DistFiles->'%(FullPath)')" Exclude="@(ResolvedFileToPublish)">
      <RelativePath>wwwroot\%(RecursiveDir)%(FileName)%(Extension)</RelativePath>
      <CopyToPublishDirectory>PreserveNewest</CopyToPublishDirectory>
      <ExcludeFromSingleFile>true</ExcludeFromSingleFile>
    </ResolvedFileToPublish>
  </ItemGroup>
</Target>
```

For **React** (output goes to `build\`):
```xml
<Target Name="DebugEnsureNodeEnv" BeforeTargets="Build" Condition=" '$(Configuration)' == 'Debug' And !Exists('$(SpaRoot)node_modules') ">
  <Exec Command="node --version" ContinueOnError="true">
    <Output TaskParameter="ExitCode" PropertyName="ErrorCode" />
  </Exec>
  <Error Condition="'$(ErrorCode)' != '0'" Text="Node.js is required to build and run this project. To continue, please install Node.js from https://nodejs.org/, and then restart your command prompt or IDE." />
  <Message Importance="high" Text="Restoring dependencies using 'npm'. This may take several minutes..." />
  <Exec WorkingDirectory="$(SpaRoot)" Command="npm install" />
</Target>

<Target Name="PublishRunWebpack" AfterTargets="ComputeFilesToPublish">
  <Exec WorkingDirectory="$(SpaRoot)" Command="npm install" />
  <Exec WorkingDirectory="$(SpaRoot)" Command="npm run build" />
  <ItemGroup>
    <DistFiles Include="$(SpaRoot)build\**" />
    <ResolvedFileToPublish Include="@(DistFiles->'%(FullPath)')" Exclude="@(ResolvedFileToPublish)">
      <RelativePath>wwwroot\%(RecursiveDir)%(FileName)%(Extension)</RelativePath>
      <CopyToPublishDirectory>PreserveNewest</CopyToPublishDirectory>
      <ExcludeFromSingleFile>true</ExcludeFromSingleFile>
    </ResolvedFileToPublish>
  </ItemGroup>
</Target>
```

### Step 4: Update launchSettings.json

Add the hosting startup assembly environment variable to **each profile** inside the `profiles` section:
```json
"ASPNETCORE_HOSTINGSTARTUPASSEMBLIES": "Microsoft.AspNetCore.SpaProxy"
```

Ensure the backend `applicationUrl` port differs from the frontend `SpaProxyServerUrl` port.

### Step 5: Update package.json

#### Angular

Add cross-platform start scripts with SSL using the ASP.NET Core dev certificate. Replace the frontend port to match `SpaProxyServerUrl`:
```json
"start": "run-script-os",
"start:windows": "ng serve --port 44416 --ssl --ssl-cert %APPDATA%\\ASP.NET\\https\\%npm_package_name%.pem --ssl-key %APPDATA%\\ASP.NET\\https\\%npm_package_name%.key",
"start:default": "ng serve --port 44416 --ssl --ssl-cert $HOME/.aspnet/https/${npm_package_name}.pem --ssl-key $HOME/.aspnet/https/${npm_package_name}.key",
```

Add the `run-script-os` dependency:
```json
"run-script-os": "^1.1.6"
```

#### React

Update start scripts to run HTTPS setup before launching the dev server:
```json
"prestart": "node aspnetcore-https && node aspnetcore-react",
"start": "rimraf ./build && react-scripts start"
```

### Step 6: Update angular.json (Angular Only)

Add a proxy configuration to the development serve target:
```json
"serve": {
  "configurations": {
    "development": {
      "proxyConfig": "proxy.conf.js"
    }
  }
}
```

### Step 7: Add HTTPS and Proxy Configuration Files

Add these files in the same directory as `package.json` (typically `ClientApp/`).

#### aspnetcore-https.js (Angular and React)

Sets up HTTPS using the ASP.NET Core development certificate:
```js
// This script sets up HTTPS for the application using the ASP.NET Core HTTPS certificate
const fs = require('fs');
const spawn = require('child_process').spawn;
const path = require('path');

const baseFolder =
  process.env.APPDATA !== undefined && process.env.APPDATA !== ''
    ? `${process.env.APPDATA}/ASP.NET/https`
    : `${process.env.HOME}/.aspnet/https`;

const certificateArg = process.argv.map(arg => arg.match(/--name=(?<value>.+)/i)).filter(Boolean)[0];
const certificateName = certificateArg ? certificateArg.groups.value : process.env.npm_package_name;

if (!certificateName) {
  console.error('Invalid certificate name. Run this script in the context of an npm/yarn script or pass --name=<<app>> explicitly.')
  process.exit(-1);
}

const certFilePath = path.join(baseFolder, `${certificateName}.pem`);
const keyFilePath = path.join(baseFolder, `${certificateName}.key`);

if (!fs.existsSync(certFilePath) || !fs.existsSync(keyFilePath)) {
  spawn('dotnet', [
    'dev-certs',
    'https',
    '--export-path',
    certFilePath,
    '--format',
    'Pem',
    '--no-password',
  ], { stdio: 'inherit', })
  .on('exit', (code) => process.exit(code));
}
```

#### proxy.conf.js (Angular Only)

Proxies API requests to the ASP.NET Core backend. Replace `[IIS-HTTP-PORT]` with the IIS Express port from `Properties/launchSettings.json`, and update the `context` array with the project's API route prefixes:
```js
const { env } = require('process');

const target = env.ASPNETCORE_HTTPS_PORT ? `https://localhost:${env.ASPNETCORE_HTTPS_PORT}` :
  env.ASPNETCORE_URLS ? env.ASPNETCORE_URLS.split(';')[0] : 'http://localhost:[IIS-HTTP-PORT]';

const PROXY_CONFIG = [
  {
    context: [
      "/weatherforecast",
    ],
    target: target,
    secure: false,
    headers: {
      Connection: 'Keep-Alive'
    }
  }
]

module.exports = PROXY_CONFIG;
```

#### aspnetcore-react.js (React Only)

Configures `.env.development.local` with SSL certificate paths for the React dev server:
```js
const fs = require('fs');
const path = require('path');

const baseFolder =
  process.env.APPDATA !== undefined && process.env.APPDATA !== ''
    ? `${process.env.APPDATA}/ASP.NET/https`
    : `${process.env.HOME}/.aspnet/https`;

const certificateArg = process.argv.map(arg => arg.match(/--name=(?<value>.+)/i)).filter(Boolean)[0];
const certificateName = certificateArg ? certificateArg.groups.value : process.env.npm_package_name;

if (!certificateName) {
  console.error('Invalid certificate name. Run this script in the context of an npm/yarn script or pass --name=<<app>> explicitly.')
  process.exit(-1);
}

const certFilePath = path.join(baseFolder, `${certificateName}.pem`);
const keyFilePath = path.join(baseFolder, `${certificateName}.key`);

if (!fs.existsSync('.env.development.local')) {
  fs.writeFileSync(
    '.env.development.local',
`SSL_CRT_FILE=${certFilePath}
SSL_KEY_FILE=${keyFilePath}`
  );
} else {
  let lines = fs.readFileSync('.env.development.local')
    .toString()
    .split('\n');

  let hasCert, hasCertKey = false;
  for (const line of lines) {
    if (/SSL_CRT_FILE=.*/i.test(line)) {
      hasCert = true;
    }
    if (/SSL_KEY_FILE=.*/i.test(line)) {
      hasCertKey = true;
    }
  }
  if (!hasCert) {
    fs.appendFileSync(
      '.env.development.local',
      `\nSSL_CRT_FILE=${certFilePath}`
    );
  }
  if (!hasCertKey) {
    fs.appendFileSync(
      '.env.development.local',
      `\nSSL_KEY_FILE=${keyFilePath}`
    );
  }
}
```

#### .env.development (React Only)

Add in the same folder as `package.json`. Replace the port to match `SpaProxyServerUrl`:
```
PORT=44416
HTTPS=true
```

#### setupProxy.js (React Only)

Add inside `ClientApp/src/`. Replace `[IIS-HTTP-PORT]` with the IIS Express port from `Properties/launchSettings.json`, and update the `context` array with the project's API route prefixes:
```js
const { createProxyMiddleware } = require('http-proxy-middleware');
const { env } = require('process');

const target = env.ASPNETCORE_HTTPS_PORT ? `https://localhost:${env.ASPNETCORE_HTTPS_PORT}` :
  env.ASPNETCORE_URLS ? env.ASPNETCORE_URLS.split(';')[0] : 'http://localhost:[IIS-HTTP-PORT]';

const context = [
  "/weatherforecast",
];

module.exports = function(app) {
  const appProxy = createProxyMiddleware(context, {
    target: target,
    secure: false,
    headers: {
      Connection: 'Keep-Alive'
    }
  });

  app.use(appProxy);
};
```

### Step 8: Build and Verify

1. Build: `dotnet build`
2. Run: `dotnet run`
3. Verify the SPA proxy page appears briefly before redirecting to the frontend
4. Confirm hot-reload works in the frontend dev server
5. Test production publish: `dotnet publish` — verify the SPA output lands in `wwwroot/`

## File Summary by Framework

| File | Angular | React |
|------|---------|-------|
| Startup.cs changes | ✅ | ✅ |
| Project file changes | ✅ (dist output) | ✅ (build output) |
| launchSettings.json | ✅ | ✅ |
| package.json (start scripts) | ✅ (run-script-os) | ✅ (prestart + react-scripts) |
| angular.json | ✅ | — |
| aspnetcore-https.js | ✅ | ✅ |
| proxy.conf.js | ✅ | — |
| aspnetcore-react.js | — | ✅ |
| .env.development | — | ✅ |
| setupProxy.js (in src/) | — | ✅ |

## Troubleshooting

### SPA Proxy Page Shows But Never Redirects

The frontend dev server is not starting or is listening on the wrong port. Verify `SpaProxyLaunchCommand` is correct and `SpaProxyServerUrl` matches the actual dev server URL.

### HTTPS Certificate Errors

The dev server certificate is not trusted. Run `dotnet dev-certs https --trust` and ensure `aspnetcore-https.js` exported the certificate to the correct path.

### Port Conflicts

The backend `applicationUrl` and frontend `SpaProxyServerUrl` must use different ports. Conflicting ports cause connection refused errors.

### Static Files Not Served in Production

`SpaProxy` is development-only. For production, the `PublishRunWebpack` target in the project file must copy the SPA build output to `wwwroot/`. Verify the `DistFiles` include pattern matches the framework's output directory (`dist\` for Angular, `build\` for React).
