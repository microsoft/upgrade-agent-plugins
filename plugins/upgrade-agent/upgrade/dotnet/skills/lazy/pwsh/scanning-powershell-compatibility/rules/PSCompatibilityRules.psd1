# Copyright (c) Microsoft Corporation. All rights reserved.
#
# Windows PowerShell 5.1 -> PowerShell 7.x compatibility rule catalog.
#
# Read in Stage 1 Assessment by both scanners, in two different roles:
#   Step 3a, Invoke-PSSACompatibilityScan.ps1 -- reads the knowledge-only rules
#            (those carrying SupersededBy) and joins them onto PSScriptAnalyzer's
#            output to add the Category, Severity, Remediation and Skill routing
#            the analyzer does not produce.
#   Step 3b, Get-PSCompatibilityScan.ps1 -- runs the active rules (those without
#            SupersededBy) as the sidecar detector for what the analyzer cannot
#            see.
# One rule is therefore either a detector or a knowledge entry, never both, and
# every rule carries the routing metadata regardless.
#
# This file is DATA ONLY. It is loaded with Import-PowerShellDataFile, which
# parses restricted data-language literals and never evaluates code, so a rule
# file cannot execute anything. Keep it that way: no script blocks, no
# expressions, no regexes that get compiled into behaviour. A rule that needs
# code belongs in a new Kind implemented in Get-PSCompatibilityScan.ps1.
#
# Sourced from the official documentation:
#   https://learn.microsoft.com/powershell/scripting/whats-new/differences-from-windows-powershell
#
# To extend or override: see "Extending the catalog" in SKILL.md. Do not edit
# this file in place inside a customer repo -- supply your own via -RulesPath.
#
# Schema
# ------
#   Id          Stable identifier. Used as the join key in scan-findings.csv,
#               in plan tasks, and in the execution re-scan gate. Never reuse.
#   Kind        Selects the matcher. One of:
#                 Command          command-position name (cmdlet, function, alias)
#                 Keyword          language keyword
#                 Type             type literal - [wmi], [System.Windows.Forms.Form]
#                                  also matches the type argument of New-Object
#                 StringLiteral    substring of a string constant
#                 MemberAccess     member name on any expression - $r.ParsedHtml
#                 StaticMember     static member qualified by its owning type -
#                                  'Text.Encoding::Default'. Match is a dotted
#                                  suffix, so it fires on both the full and the
#                                  shortened type name. Use this instead of
#                                  MemberAccess whenever the member name alone is
#                                  too common to be meaningful.
#                 CommandArgument  literal argument of OnCommand
#                 Parameter        named parameter present on OnCommand
#                 ParameterValue   named parameter with a specific literal value
#                 MissingParameter OnCommand invoked WITHOUT the named parameter
#                 Module           module name in Import-Module/using module/#Requires
#                 RequiresEdition  #Requires -PSEdition <value>
#                 RequiresVersion  #Requires -Version <major>
#                 NullComparison   structural: -eq/-ne with $null on the right
#                 FileRedirection  structural: > and >> file redirection
#                                  (2>&1-style merges are a different AST type
#                                  and never match; '> $null' is skipped)
#   Match       Values the matcher compares against (case-insensitive).
#               MatchMode 'Exact' (default) or 'Contains'.
#   OnCommand   Restricts Parameter/ParameterValue/MissingParameter rules to
#               these commands.
#   OnParameter Used by ParameterValue rules only. Names the parameter whose
#               bound value is compared against Match. Parameter and
#               MissingParameter rules instead put the parameter name(s) in Match.
#   RequiresParameter
#               Used by MissingParameter rules only. The rule fires only when the
#               invocation ALSO binds at least one of these parameters, which
#               narrows it to the form that actually breaks instead of every call
#               that omits the parameter. Prefixes resolve, as everywhere else.
#   Severity    Blocker | Manual | AutoFix | Advisory. See SKILL.md.
#   Supersedes  Ids this rule replaces when both fire on the same line, so a
#               single remediation is not double-counted.
#   SupersededBy
#               Name of an *external* analyzer rule that already detects this
#               class, normally 'PSUseCompatibleCommands'. A rule carrying this
#               key is KNOWLEDGE-ONLY: it is filtered out before matching, never
#               runs, and never emits a finding. Its Remediation/Skill text is
#               still read by the triage skill, which joins it to the analyzer's
#               finding by CatalogRuleId to add the identity and routing
#               PSScriptAnalyzer does not produce. Add this key only once the
#               analyzer is confirmed to detect the same sites; see
#               'Relationship to PSScriptAnalyzer' in SKILL.md.
#   Skill       Remediation skill to load when this rule fires. Emitted into
#               the plan as a '#skill:' marker.

@{
    SchemaVersion = 1

    Rules         = @(

        # -- Removed: snap-ins ------------------------------------------------

        @{
            Id          = 'snapin'
            SupersededBy = 'PSUseCompatibleCommands'
            Kind        = 'Command'
            Match       = @('Add-PSSnapin', 'Get-PSSnapin', 'Remove-PSSnapin', 'asnp', 'gsnp', 'rsnp', 'Export-Console')
            Category    = 'PSSnapin'
            Severity    = 'Blocker'
            Remediation = 'Snap-ins do not exist in PowerShell 7 -- the whole mechanism was removed, so there is no in-process replacement. Import the equivalent module, or reach the snap-in through implicit remoting against a Windows PowerShell 5.1 endpoint (New-PSSession + Import-PSSession).'
            Skill       = 'handling-removed-snapins'
        }

        @{
            Id          = 'exchange-snapin'
            # CommandArgument, not StringLiteral: the snap-in name has to be an
            # argument of a snap-in cmdlet to mean anything. Matching the bare
            # string also hit documentation, here-strings and test fixtures, and
            # this is a Blocker, so a false positive here is expensive.
            Kind        = 'CommandArgument'
            Match       = @('Microsoft.Exchange.Management.PowerShell')
            MatchMode   = 'Contains'
            OnCommand   = @('Add-PSSnapin', 'asnp', 'Get-PSSnapin', 'gsnp', 'Remove-PSSnapin', 'rsnp')
            Category    = 'PSSnapin'
            Severity    = 'Blocker'
            Supersedes  = @('snapin')
            Remediation = 'The Exchange management snap-in cannot load in PowerShell 7. Connect with implicit remoting (New-PSSession -ConfigurationName Microsoft.Exchange) or move to the Exchange Online REST module.'
            Skill       = 'handling-removed-snapins'
        }

        # -- Removed: WMI v1 --------------------------------------------------

        @{
            Id          = 'wmi-cmdlet'
            SupersededBy = 'PSUseCompatibleCommands'
            Kind        = 'Command'
            Match       = @('Get-WmiObject', 'gwmi', 'Invoke-WmiMethod', 'iwmi', 'Register-WmiEvent',
                'Set-WmiInstance', 'swmi', 'Remove-WmiObject', 'rwmi')
            Category    = 'Wmi'
            Severity    = 'Blocker'
            Remediation = 'The WMI v1 cmdlets are removed in PowerShell 7. Migrate to the CIM cmdlets: Get-CimInstance, Invoke-CimMethod, Set-CimInstance, Remove-CimInstance, Register-CimIndicationEvent.'
            Skill       = 'migrating-wmi-to-cim'
        }

        @{
            Id          = 'wmi-accelerator'
            Kind        = 'Type'
            Match       = @('wmi', 'wmiclass', 'wmisearcher')
            Category    = 'Wmi'
            Severity    = 'Blocker'
            Remediation = 'The [wmi], [wmiclass] and [wmisearcher] type accelerators are removed in PowerShell 7. Use Get-CimInstance (by key or -Query) and Invoke-CimMethod.'
            Skill       = 'migrating-wmi-to-cim'
        }

        @{
            Id          = 'export-binarymilog'
            SupersededBy = 'PSUseCompatibleCommands'
            Kind        = 'Command'
            # Both halves of the pair. This rule no longer detects -- PSSA does --
            # but the enrichment join is keyed on the command name, so a missing
            # entry means the analyzer's finding ships with no remediation.
            Match       = @('Export-BinaryMiLog', 'Import-BinaryMiLog')
            Category    = 'RemovedCmdlet'
            Severity    = 'Blocker'
            Remediation = 'The BinaryMiLog serialization pair is removed in PowerShell 7. Persist CIM results with Export-Clixml/Import-Clixml, or Export-Csv/Import-Csv where the shape is flat. Note that an existing .bmil file cannot be read back at all under PowerShell 7, so any archived data has to be converted while 5.1 is still available.'
        }

        # -- Removed: event log -----------------------------------------------

        @{
            Id          = 'eventlog-cmdlet'
            SupersededBy = 'PSUseCompatibleCommands'
            Kind        = 'Command'
            Match       = @('Get-EventLog', 'Write-EventLog', 'New-EventLog', 'Clear-EventLog',
                'Limit-EventLog', 'Show-EventLog', 'Remove-EventLog')
            Category    = 'EventLog'
            Severity    = 'Blocker'
            Remediation = 'The *-EventLog cmdlets are removed in PowerShell 7. Read with Get-WinEvent, write with New-WinEvent, and fall back to System.Diagnostics.EventLog for log administration (creating and removing sources).'
            Skill       = 'replacing-eventlog-with-winevent'
        }

        # -- Removed: computer management -------------------------------------

        @{
            Id          = 'computer-cmdlet'
            SupersededBy = 'PSUseCompatibleCommands'
            Kind        = 'Command'
            Match       = @('Add-Computer', 'Remove-Computer', 'Checkpoint-Computer', 'Restore-Computer',
                'Enable-ComputerRestore', 'Disable-ComputerRestore', 'Get-ComputerRestorePoint',
                'Reset-ComputerMachinePassword', 'Test-ComputerSecureChannel')
            Category    = 'RemovedCmdlet'
            Severity    = 'Blocker'
            Remediation = 'These domain-join and system-restore cmdlets are removed in PowerShell 7. Use the DISM/CIM equivalents, the ActiveDirectory module over the compatibility layer, or run this specific step under Windows PowerShell 5.1.'
        }

        @{
            Id          = 'controlpanel-cmdlet'
            SupersededBy = 'PSUseCompatibleCommands'
            Kind        = 'Command'
            Match       = @('Get-ControlPanelItem', 'Show-ControlPanelItem')
            Category    = 'RemovedCmdlet'
            Severity    = 'Blocker'
            Remediation = 'The *-ControlPanelItem cmdlets are removed in PowerShell 7. Launch the control panel applet directly (control.exe / ms-settings: URI) if the behaviour is still required.'
        }

        # -- Removed: transactions, counters, workflow jobs -------------------

        @{
            Id          = 'transaction-cmdlet'
            SupersededBy = 'PSUseCompatibleCommands'
            Kind        = 'Command'
            Match       = @('Start-Transaction', 'Complete-Transaction', 'Undo-Transaction',
                'Get-Transaction', 'Use-Transaction')
            Category    = 'RemovedCmdlet'
            Severity    = 'Blocker'
            Remediation = 'Transaction support was removed in PowerShell 7 -- only the registry provider ever implemented it. Restructure the operation to be idempotent, or perform the rollback explicitly.'
        }

        @{
            Id          = 'counter-cmdlet'
            SupersededBy = 'PSUseCompatibleCommands'
            Kind        = 'Command'
            Match       = @('Export-Counter', 'Import-Counter')
            Category    = 'RemovedCmdlet'
            Severity    = 'Blocker'
            Remediation = 'Export-Counter and Import-Counter are removed in PowerShell 7. Get-Counter remains on Windows; persist its output with Export-Clixml/Export-Csv instead of the .blg format.'
        }

        @{
            Id          = 'workflow-job-cmdlet'
            SupersededBy = 'PSUseCompatibleCommands'
            Kind        = 'Command'
            Match       = @('Resume-Job', 'Suspend-Job')
            Category    = 'Workflow'
            Severity    = 'Blocker'
            Remediation = 'Resume-Job and Suspend-Job only ever applied to workflow jobs, and PSWorkflow is not shipped with PowerShell 7. Remove them along with the workflow they drive.'
        }

        @{
            Id          = 'workflow'
            SupersededBy = 'PSUseCompatibleSyntax'
            Kind        = 'Keyword'
            Match       = @('workflow')
            Category    = 'Workflow'
            Severity    = 'Blocker'
            Remediation = 'PowerShell Workflow is removed in PowerShell 7 and the keyword does not even parse ("Workflow is not supported in PowerShell 6+"). Re-implement as a normal function; use ForEach-Object -Parallel or Start-ThreadJob for the concurrency, and an external orchestrator if checkpoint/resume was genuinely relied upon.'
        }

        # -- Removed: DSC, string conversion, SOAP ----------------------------

        @{
            Id          = 'dsc-cmdlet'
            SupersededBy = 'PSUseCompatibleCommands'
            Kind        = 'Command'
            Match       = @('Disable-DscDebug', 'Enable-DscDebug', 'Get-DscConfiguration',
                'Get-DscConfigurationStatus', 'Get-DscLocalConfigurationManager', 'Publish-DscConfiguration',
                'Remove-DscConfigurationDocument', 'Restore-DscConfiguration', 'Set-DscLocalConfigurationManager',
                'Start-DscConfiguration', 'Stop-DscConfiguration', 'Test-DscConfiguration',
                'Update-DscConfiguration')
            Category    = 'Dsc'
            Severity    = 'Blocker'
            Remediation = 'The DSC configuration-management cmdlets are not shipped with PowerShell 7. DSC is now a separate product line rather than an in-box feature: PSDesiredStateConfiguration is a gallery module, and DSC v3 is a standalone cross-platform executable with a different authoring and invocation model, so this is a port rather than a cmdlet swap. Decide between moving to Azure Machine Configuration / DSC v3 and keeping the DSC step on Windows PowerShell 5.1; do not assume a drop-in replacement exists.'
        }

        @{
            Id          = 'convertfrom-string'
            SupersededBy = 'PSUseCompatibleCommands'
            Kind        = 'Command'
            Match       = @('Convert-String', 'ConvertFrom-String')
            Category    = 'RemovedCmdlet'
            Severity    = 'Blocker'
            Remediation = 'Convert-String and ConvertFrom-String are removed in PowerShell 7 (they depended on a Windows-only ML component). Parse with a regex, -split, or ConvertFrom-Csv.'
        }

        @{
            Id          = 'web-service-proxy'
            SupersededBy = 'PSUseCompatibleCommands'
            Kind        = 'Command'
            Match       = @('New-WebServiceProxy')
            Category    = 'RemovedCmdlet'
            Severity    = 'Blocker'
            Remediation = 'New-WebServiceProxy is removed in PowerShell 7 -- .NET Core has no ASMX client generator. Generate a WCF client with dotnet-svcutil, or call the endpoint with Invoke-RestMethod and hand-build the SOAP envelope.'
        }

        # -- Removed: modules not shipped with PowerShell 7 -------------------

        # The removed-module family is split by the outcome an import actually has
        # under PowerShell 7, because the remediation differs completely between
        # them and a single rule would have to state something false about most of
        # its own match list. Verify with:
        #   Import-Module <name>; (Get-Module <name>).ModuleType
        @{
            Id          = 'blocked-module'
            Kind        = 'Module'
            Match       = @('PSScheduledJob')
            Category    = 'RemovedModule'
            Severity    = 'Blocker'
            Remediation = 'PowerShell 7 refuses to load this module even through the compatibility layer -- it is on the WindowsPowerShell compatibility block list, so Import-Module -UseWindowsPowerShell does not rescue it either. Move scheduled work to ScheduledTasks (Register-ScheduledTask) or to the platform scheduler, and redesign the calling code.'
            Skill       = 'fixing-windows-only-modules'
        }
        @{
            Id          = 'unavailable-module'
            Kind        = 'Module'
            Match       = @('ISE', 'Microsoft.PowerShell.ISE')
            Category    = 'RemovedModule'
            Severity    = 'Blocker'
            Remediation = 'The ISE object model does not exist in PowerShell 7 -- there is no host to automate and no shim. Any $psISE access has to be removed. If the script exists to drive the editor, it has no PowerShell 7 equivalent; if it merely uses ISE as a convenient host, decouple it and run it as a plain script.'
            Skill       = 'fixing-windows-only-modules'
        }
        @{
            Id          = 'winpscompat-module'
            Kind        = 'Module'
            Match       = @('Microsoft.PowerShell.ODataUtils', 'PSWorkflow', 'PSWorkflowUtility')
            Category    = 'RemovedModule'
            Severity    = 'Manual'
            Remediation = 'This module is not shipped for PowerShell 7 but still imports, silently, through the Windows PowerShell compatibility layer: PowerShell 7 starts a hidden 5.1 child process and proxies the commands. The script therefore keeps working while remaining Windows-only and dependent on 5.1 being installed, and every returned object is deserialized so its methods are gone. Confirm which it is with (Get-PSSession -Name WinPSCompatSession). Treat a proxied import as deferred, not migrated: workflows have no PowerShell 7 equivalent and need redesign (parallel foreach, jobs, or an external orchestrator), and ODataUtils has no successor.'
            Skill       = 'fixing-windows-only-modules'
        }
        @{
            Id          = 'native-in-ps7-module'
            Kind        = 'Module'
            Match       = @('Microsoft.PowerShell.LocalAccounts', 'Microsoft.PowerShell.Operation.Validation')
            Category    = 'RemovedModule'
            Severity    = 'Advisory'
            Remediation = 'This module is often listed as Windows-PowerShell-only, but current PowerShell 7 on Windows imports it natively and in-process -- no compatibility session is involved. Verify on the exact target build before spending any migration effort here, and expect no change. It remains Windows-only, so it is still a portability blocker if the target is Linux or macOS.'
            Skill       = 'fixing-windows-only-modules'
        }

        # -- Hard stop: the script refuses to run at all -----------------------

        @{
            Id          = 'requires-psedition-desktop'
            Kind        = 'RequiresEdition'
            Match       = @('Desktop')
            Category    = 'Requires'
            Severity    = 'Blocker'
            Remediation = "'#Requires -PSEdition Desktop' makes PowerShell 7 (edition Core) refuse to run the script outright, before a single statement executes. Drop the directive once the script is PS7-clean, or change it to Core if it must never run under 5.1 again."
        }

        # -- Blocker: .NET Framework surface that PowerShell 7 does not carry ----

        @{
            Id          = 'framework-only-namespace'
            Kind        = 'Type'
            Match       = @('System.Web.Security.', 'System.Web.Script.', 'System.Web.UI.',
                'System.Web.Services.', 'System.Runtime.Remoting.', 'System.EnterpriseServices.',
                'System.Runtime.Serialization.Formatters.Binary.')
            MatchMode   = 'Contains'
            Category    = 'DotNetApi'
            Severity    = 'Blocker'
            Remediation = 'These namespaces are .NET Framework only; .NET (and therefore PowerShell 7) never carried them. Some fail immediately at type resolution, but others are worse: on Windows, Add-Type can still pull the Framework assembly out of the GAC and the type will bind, so the script appears to work until the first real call throws TypeLoadException. Treat a successful load as no evidence of support -- exercise the code path. There is no shim; replace the API. Common substitutions: JavaScriptSerializer -> ConvertTo-Json/ConvertFrom-Json or System.Text.Json; System.Web.Security.Membership -> a supported identity or hashing library; BinaryFormatter -> a versioned contract format such as JSON; .NET Remoting and EnterpriseServices -> an out-of-process protocol the target platform supports.'
        }

        @{
            Id          = 'encoding-default'
            Kind        = 'StaticMember'
            Match       = @('Text.Encoding::Default')
            Category    = 'DotNetApi'
            Severity    = 'Blocker'
            Remediation = "[Text.Encoding]::Default is the system ANSI code page on Windows PowerShell 5.1 and UTF-8 on PowerShell 7. Nothing throws -- the same code silently reads and writes different bytes, so this corrupts non-ASCII data rather than failing. Name the encoding the data actually uses: [Text.Encoding]::GetEncoding(1252) (or the correct code page) to preserve the existing behaviour, or [Text.Encoding]::UTF8 if the intent was always UTF-8. Other [Text.Encoding] members are unaffected."
            Skill       = 'powershell-mechanical-fixups'
        }

        # -- Manual: works only through a compatibility layer ------------------

        @{
            Id          = 'windows-only-module'
            Kind        = 'Module'
            Match       = @('ActiveDirectory', 'ServerManager', 'Hyper-V', 'FailoverClusters', 'BitLocker',
                'NetSecurity', 'Dism', 'Storage', 'ScheduledTasks', 'WebAdministration', 'GroupPolicy',
                'NetAdapter', 'NetTCPIP', 'SmbShare', 'PrintManagement', 'DnsServer', 'DhcpServer')
            Category    = 'WindowsModule'
            Severity    = 'Manual'
            Remediation = 'This module is Windows-specific, and how it behaves under PowerShell 7 varies by module and by build -- so establish the actual outcome before planning any work. Many of these are CDXML/CIM based and import natively once the RSAT or optional feature is installed; others only load through the compatibility layer. Try a native import first, then a PS7-targeted successor module (WebAdministration -> IISAdministration), then implicit remoting to a server that has it. Import-Module -UseWindowsPowerShell is the last resort: it proxies into a hidden Windows PowerShell 5.1 child process, so the script still requires 5.1 locally and stays Windows-only. Record that outcome as deferred, not remediated. Proxied objects come back deserialized, so methods on them are gone -- verify every property access and method call downstream. Either way the module is a portability blocker if the target is Linux or macOS.'
            Skill       = 'fixing-windows-only-modules'
        }

        @{
            Id          = 'servicepointmanager'
            Kind        = 'Type'
            Match       = @('ServicePointManager')
            MatchMode   = 'Contains'
            Category    = 'DotNetApi'
            Severity    = 'Manual'
            Remediation = 'ServicePointManager configures the legacy HttpWebRequest stack. PowerShell 7 web cmdlets are built on HttpClient and ignore it, so the type still resolves and the assignment still succeeds while having no effect. Which members matter differs: setting SecurityProtocol is usually a harmless no-op, since PS7 negotiates TLS through the OS. ServerCertificateValidationCallback and CertificatePolicy are the dangerous ones -- a script that relied on either to accept a private or self-signed certificate will start failing its TLS handshake, and one that used it to bypass validation loses that bypass silently. Replace per-request: Invoke-WebRequest/Invoke-RestMethod -SkipCertificateCheck, or -Certificate for client authentication. Code still calling HttpWebRequest directly is unaffected.'
        }

        @{
            Id          = 'com-object'
            Kind        = 'Parameter'
            Match       = @('ComObject')
            OnCommand   = @('New-Object')
            Category    = 'Com'
            Severity    = 'Manual'
            Remediation = 'COM interop works on Windows builds of PowerShell 7 but marshalling differs in places, and it is unavailable on Linux and macOS. Verify the specific component on pwsh; if the script must stay cross-platform, replace the COM dependency.'
        }

        @{
            Id          = 'windows-only-gui'
            Kind        = 'Type'
            Match       = @('System.Windows.Forms', 'System.Windows.Media', 'PresentationFramework',
                'PresentationCore')
            MatchMode   = 'Contains'
            Category    = 'Gui'
            Severity    = 'Manual'
            Remediation = 'Not a version blocker: .NET Core 3.1 restored WinForms/WPF and PowerShell 7.0 brought back Out-GridView, Show-Command and Get-Help -ShowWindow. It is a *platform* constraint -- these types exist only on Windows builds of PowerShell 7. Keep the script Windows-only, or replace the UI.'
        }

        @{
            Id          = 'windows-only-assembly'
            Kind        = 'ParameterValue'
            OnCommand   = @('Add-Type')
            OnParameter = 'AssemblyName'
            Match       = @('System.Windows.Forms', 'PresentationFramework', 'PresentationCore',
                'WindowsBase', 'System.Drawing')
            Category    = 'Gui'
            Severity    = 'Manual'
            Remediation = 'Add-Type -AssemblyName loads the desktop assemblies by name, so no type literal appears in the script and the type-based windows-only-gui rule cannot see it. These load fine on Windows builds of PowerShell 7 (verified on 7.6), so this is a platform constraint, not a version blocker -- it fails on Linux and macOS, and System.Drawing additionally throws PlatformNotSupportedException off Windows on .NET 6+. Keep the script Windows-only, or replace the UI/graphics dependency.'
        }

        # -- AutoFix: deterministic mechanical rewrite -------------------------

        @{
            Id          = 'encoding-byte'
            Kind        = 'ParameterValue'
            Match       = @('Byte')
            # Out-File is deliberately absent: its -Encoding ValidateSet never
            # accepted Byte, on 5.1 or 7, so a match there could only be code that
            # was already broken.
            OnCommand   = @('Get-Content', 'Set-Content', 'Add-Content')
            OnParameter = 'Encoding'
            Category    = 'MechanicalFix'
            Severity    = 'AutoFix'
            Remediation = "'-Encoding Byte' is removed in PowerShell 7. Replace with '-AsByteStream'."
            Skill       = 'powershell-mechanical-fixups'
        }

        @{
            Id          = 'powershell-exe'
            Kind        = 'StringLiteral'
            Match       = @('powershell.exe')
            MatchMode   = 'Contains'
            Category    = 'MechanicalFix'
            # Manual, not AutoFix. The match is textual and context-blind, so it
            # also fires on documentation, error messages and test fixtures --
            # 'Write-Host "do not call powershell.exe"' is a match. AutoFix asserts
            # a rewrite is mechanically safe, which cannot be asserted here. The
            # broad match is kept deliberately: the real sites include assignments
            # and scheduled-task action strings that no invocation-shaped matcher
            # would reach, and a missed one leaves a script silently on 5.1.
            Severity    = 'Manual'
            Remediation = "A hardcoded 'powershell.exe' launches Windows PowerShell 5.1, so that child process is still on the old engine no matter what the parent is running. Replace with 'pwsh' -- but confirm the string is an invocation first. Matching is textual, so prose, log messages and test data match too; leave those alone."
            Skill       = 'powershell-mechanical-fixups'
        }

        # -- Advisory: still runs, but the behaviour changed -------------------

        # Six *-output-encoding rules, split by observed behaviour rather than by
        # cmdlet family, because that split decides whether "our data is all ASCII"
        # dismisses the finding. With pure-ASCII content, written on 5.1 then on 7:
        #   Out-File / Export-Clixml / Tee-Object / >    UTF-16LE+BOM -> UTF-8 no BOM
        #   Set-Content / Add-Content / Export-Csv       byte-identical
        # The first group rewrites every byte of the file whatever the content, so it
        # cannot be reasoned away; the second differs only where the data is non-ASCII.
        # Keep them as separate ids so that distinction survives into the plan.

        @{
            Id          = 'outfile-output-encoding'
            Kind        = 'MissingParameter'
            Match       = @('Encoding')
            OnCommand   = @('Out-File')
            Category    = 'MechanicalFix'
            Severity    = 'Advisory'
            Remediation = 'No explicit -Encoding on Out-File. Windows PowerShell wrote UTF-16LE with a BOM; PowerShell 7 writes UTF-8 with no BOM. Every file written by this call changes on disk -- including pure-ASCII content, because of the BOM and the 2-byte encoding -- so any downstream reader that is not encoding-aware breaks silently. Pin -Encoding to whatever the consumer requires; -Encoding Unicode reproduces the 5.1 bytes exactly.'
            Skill       = 'powershell-mechanical-fixups'
        }

        @{
            Id          = 'clixml-output-encoding'
            Kind        = 'MissingParameter'
            Match       = @('Encoding')
            OnCommand   = @('Export-Clixml')
            Category    = 'MechanicalFix'
            Severity    = 'Advisory'
            Remediation = 'No explicit -Encoding on Export-Clixml. Windows PowerShell wrote UTF-16LE with a BOM; PowerShell 7 writes UTF-8 with no BOM, so every byte of the file changes even for pure-ASCII content. This is serialized state handed to another process, so a reader that is not encoding-aware fails outright rather than degrading. PSScriptAnalyzer cannot see this -- the cmdlet exists unchanged in both editions. Pin -Encoding to what the consumer requires; -Encoding Unicode reproduces the 5.1 bytes exactly.'
            Skill       = 'powershell-mechanical-fixups'
        }

        @{
            Id                = 'tee-output-encoding'
            Kind              = 'MissingParameter'
            Match             = @('Encoding')
            OnCommand         = @('Tee-Object')
            RequiresParameter = @('FilePath')
            Category          = 'MechanicalFix'
            Severity          = 'Advisory'
            Remediation       = 'No explicit -Encoding on Tee-Object -FilePath. Windows PowerShell wrote UTF-16LE with a BOM; PowerShell 7 writes UTF-8 with no BOM, so the tee''d file changes on disk even for pure-ASCII content. Note -Encoding does not exist on Tee-Object in Windows PowerShell 5.1, so adding it breaks a script that must still run under both editions -- in that case tee via "| Out-File -Encoding unicode" instead. Only applies when -FilePath is used; teeing to a variable is unaffected.'
            Skill             = 'powershell-mechanical-fixups'
        }

        @{
            Id          = 'redirection-output-encoding'
            Kind        = 'FileRedirection'
            Match       = @('>', '>>')
            Category    = 'MechanicalFix'
            Severity    = 'Advisory'
            Remediation = 'For PowerShell object output, redirection is Out-File with no way to pass -Encoding, so it silently inherits the default: UTF-16LE with a BOM under Windows PowerShell, UTF-8 with no BOM under PowerShell 7. The bytes change for every file, including pure-ASCII content. There is no in-place fix -- rewrite as "| Out-File -Encoding <enc> <path>" (or Set-Content) and pin the encoding the consumer expects. The equivalence does not hold for a *native* command: since PowerShell 7.4 the stdout of an external executable redirected with > is written through as raw bytes rather than being decoded and re-encoded, so those sites may need no change at all -- check which side of the redirect you are on before rewriting. Redirection to $null and stream merges such as 2>&1 are not reported.'
            Skill       = 'powershell-mechanical-fixups'
        }

        @{
            Id          = 'ansi-output-encoding'
            Kind        = 'MissingParameter'
            Match       = @('Encoding')
            OnCommand   = @('Set-Content', 'Add-Content')
            Category    = 'MechanicalFix'
            Severity    = 'Advisory'
            Remediation = 'No explicit -Encoding. Windows PowerShell wrote the active ANSI code page (Windows-1252 on a US install); PowerShell 7 writes UTF-8 with no BOM. Pure-ASCII content is byte-identical, so this only matters where the data can contain non-ASCII -- names, paths, or anything user-supplied. Pin -Encoding where that is possible.'
            Skill       = 'powershell-mechanical-fixups'
        }

        @{
            Id          = 'csv-output-encoding'
            Kind        = 'MissingParameter'
            Match       = @('Encoding')
            OnCommand   = @('Export-Csv')
            Category    = 'MechanicalFix'
            Severity    = 'Advisory'
            Remediation = 'No explicit -Encoding. Windows PowerShell wrote ASCII and replaced every non-ASCII character with a literal "?" -- the data was already being corrupted. PowerShell 7 writes UTF-8 with no BOM and preserves it. Pure-ASCII content is byte-identical, so this is usually a latent bug being fixed rather than one being introduced; flag it only so a consumer that was parsing the "?" is not surprised.'
            Skill       = 'powershell-mechanical-fixups'
        }

        @{
            Id          = 'send-mailmessage'
            Kind        = 'Command'
            Match       = @('Send-MailMessage')
            Category    = 'Deprecated'
            Severity    = 'Advisory'
            Remediation = 'Send-MailMessage still exists in PowerShell 7 but is officially obsolete and emits a warning -- it cannot guarantee secure connections to modern SMTP servers. Not a migration blocker; move to a supported SMTP client or Microsoft Graph when the code is touched anyway.'
        }

        @{
            Id          = 'dcom-protocol'
            SupersededBy = 'PSUseCompatibleCommands'
            Kind        = 'Parameter'
            Match       = @('Protocol')
            OnCommand   = @('Rename-Computer', 'Restart-Computer', 'Stop-Computer')
            Category    = 'Remoting'
            Severity    = 'Blocker'
            Remediation = 'The -Protocol parameter is removed from the *-Computer cmdlets in PowerShell 7; DCOM remoting is no longer supported. Only WSMan remains, so drop the parameter and make sure WinRM is reachable on the target.'
        }

        @{
            Id          = 'service-computername'
            SupersededBy = 'PSUseCompatibleCommands'
            Kind        = 'Parameter'
            Match       = @('ComputerName')
            OnCommand   = @('Get-Service', 'Set-Service', 'Start-Service', 'Stop-Service',
                'Restart-Service', 'Suspend-Service', 'Resume-Service')
            Category    = 'Remoting'
            Severity    = 'Blocker'
            Remediation = 'The -ComputerName parameter was removed from the *-Service cmdlets in PowerShell 7. Wrap the call in Invoke-Command -ComputerName instead.'
        }

        @{
            Id          = 'add-type-visualbasic'
            Kind        = 'ParameterValue'
            Match       = @('VisualBasic')
            OnCommand   = @('Add-Type')
            OnParameter = 'Language'
            Category    = 'RemovedFeature'
            Severity    = 'Blocker'
            Remediation = 'Add-Type no longer supports Visual Basic in PowerShell 7. Port the inline source to C#.'
        }

        @{
            Id          = 'removed-hash-algorithm'
            Kind        = 'ParameterValue'
            Match       = @('MACTripleDES', 'RIPEMD160')
            OnCommand   = @('Get-FileHash')
            OnParameter = 'Algorithm'
            Category    = 'RemovedFeature'
            Severity    = 'Blocker'
            Remediation = 'MACTripleDES and RIPEMD160 were removed from .NET, so Get-FileHash cannot offer them in PowerShell 7. Use SHA256 or better; if the hash value must stay stable for compatibility, that is a data-format problem to resolve separately.'
        }

        @{
            Id          = 'webrequest-parsedhtml'
            # MemberAccess, so both halves of the removed pair are caught. A
            # StringLiteral rule would see the member names only where they
            # appear as text, missing '$r.Forms' entirely.
            Kind        = 'MemberAccess'
            Match       = @('ParsedHtml', 'Forms')
            Category    = 'WebCmdlet'
            Severity    = 'Manual'
            Remediation = 'Invoke-WebRequest in PowerShell 7 always returns BasicHtmlWebResponseObject -- the ParsedHtml and Forms properties are gone because the Internet Explorer DOM is no longer used. Parse the .Content string yourself (regex, HtmlAgilityPack, or an API that returns JSON). Member matching is by name only, so confirm the receiver is an Invoke-WebRequest response before acting: .Forms in particular is a common member name on unrelated objects.'
        }

        @{
            Id          = 'requires-version-5'
            Kind        = 'RequiresVersion'
            Match       = @('5')
            Category    = 'CodeQuality'
            Severity    = 'Advisory'
            Remediation = "'#Requires -Version' is a *minimum*, so this does not block PowerShell 7 -- the script still runs unchanged. It is not a migration finding; report it as optional cleanup only. Raising the floor is a deliberate policy choice that drops Windows PowerShell support, so do not raise it on any script the estate still runs on 5.1. Where dual-host support is intended, leave it alone."
        }

        @{
            Id          = 'null-on-right'
            # Knowledge-only: PSScriptAnalyzer ships PSPossibleIncorrectComparisonWithNull
            # for exactly this, and the behaviour is identical on 5.1 and 7, so it is
            # not a migration finding at all. Kept for the remediation text.
            SupersededBy = 'PSPossibleIncorrectComparisonWithNull'
            Kind        = 'NullComparison'
            Match       = @()
            Category    = 'CodeQuality'
            Severity    = 'Advisory'
            Remediation = 'Comparing against $null on the right-hand side is fragile because PowerShell unrolls arrays on the left: @() -eq $null is empty (falsy) and @($null,$null) -eq $null returns two elements. Behaviour is identical in 5.1 and 7 -- this is a latent bug, not a compatibility break, so it is optional cleanup rather than migration work. Rewrite as $null -eq $x.'
        }
    )
}
