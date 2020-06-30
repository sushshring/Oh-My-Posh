$INSTALL_PATH = "$HOME/.oh-my-posh"

# Install modules
& "$INSTALL_PATH/tools/modules.ps1"

# Handle Plugins
foreach ($plugin in $plugins) {
  Write-Verbose  "Loading from: $INSTALL_PATH/plugins/$plugin"
  $files = Get-ChildItem $INSTALL_PATH/plugins/$plugin -Filter *.ps1
  foreach ($file in $files) {
    Write-Verbose  "  Loading file: $($file.FullName)"
    . $file.FullName
  }
}

# Load theme
. "$INSTALL_PATH/themes/$theme.ps1"

# The commands to import.
$commands = "awk", "emacs", "grep", "head", "less", "ls", "man", "sed", "seq", "ssh", "tail", "vim"

# Register a function for each command.
$commands | ForEach-Object { Invoke-Expression @"
Remove-Alias $_ -Force -ErrorAction Ignore
function global:$_() {
    for (`$i = 0; `$i -lt `$args.Count; `$i++) {
        # If a path is absolute with a qualifier (e.g. C:), run it through wslpath to map it to the appropriate mount point.
        if (Split-Path `$args[`$i] -IsAbsolute -ErrorAction Ignore) {
            `$args[`$i] = Format-WslArgument (wsl.exe wslpath (`$args[`$i] -replace "\\", "/"))
        # If a path is relative, the current working directory will be translated to an appropriate mount point, so just format it.
        } elseif (Test-Path `$args[`$i] -ErrorAction Ignore) {
            `$args[`$i] = Format-WslArgument (`$args[`$i] -replace "\\", "/")
        }
    }

    if (`$input.MoveNext()) {
        `$input.Reset()
        `$input | wsl.exe $_ (`$args -split ' ')
    } else {
        wsl.exe $_ (`$args -split ' ')
    }
}
"@

}

# Register an ArgumentCompleter that shims bash's programmable completion.
Register-ArgumentCompleter -CommandName $commands -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    # Map the command to the appropriate bash completion function.
    $F = switch ($commandAst.CommandElements[0].Value) {
        {$_ -in "awk", "grep", "head", "less", "ls", "sed", "seq", "tail"} {
            "_longopt"
            break
        }

        "man" {
            "_man"
            break
        }

        "ssh" {
            "_ssh"
            break
        }

        Default {
            "_minimal"
            break
        }
    }

    # Populate bash programmable completion variables.
    $COMP_LINE = "`"$commandAst`""
    $COMP_WORDS = "('$($commandAst.CommandElements.Extent.Text -join "' '")')" -replace "''", "'"
    for ($i = 1; $i -lt $commandAst.CommandElements.Count; $i++) {
        $extent = $commandAst.CommandElements[$i].Extent
        if ($cursorPosition -lt $extent.EndColumnNumber) {
            # The cursor is in the middle of a word to complete.
            $previousWord = $commandAst.CommandElements[$i - 1].Extent.Text
            $COMP_CWORD = $i
            break
        } elseif ($cursorPosition -eq $extent.EndColumnNumber) {
            # The cursor is immediately after the current word.
            $previousWord = $extent.Text
            $COMP_CWORD = $i + 1
            break
        } elseif ($cursorPosition -lt $extent.StartColumnNumber) {
            # The cursor is within whitespace between the previous and current words.
            $previousWord = $commandAst.CommandElements[$i - 1].Extent.Text
            $COMP_CWORD = $i
            break
        } elseif ($i -eq $commandAst.CommandElements.Count - 1 -and $cursorPosition -gt $extent.EndColumnNumber) {
            # The cursor is within whitespace at the end of the line.
            $previousWord = $extent.Text
            $COMP_CWORD = $i + 1
            break
        }
    }

    # Repopulate bash programmable completion variables for scenarios like '/mnt/c/Program Files'/<TAB> where <TAB> should continue completing the quoted path.
    $currentExtent = $commandAst.CommandElements[$COMP_CWORD].Extent
    $previousExtent = $commandAst.CommandElements[$COMP_CWORD - 1].Extent
    if ($currentExtent.Text -like "/*" -and $currentExtent.StartColumnNumber -eq $previousExtent.EndColumnNumber) {
        $COMP_LINE = $COMP_LINE -replace "$($previousExtent.Text)$($currentExtent.Text)", $wordToComplete
        $COMP_WORDS = $COMP_WORDS -replace "$($previousExtent.Text) '$($currentExtent.Text)'", $wordToComplete
        $previousWord = $commandAst.CommandElements[$COMP_CWORD - 2].Extent.Text
        $COMP_CWORD -= 1
    }

    # Build the command to pass to WSL.
    $command = $commandAst.CommandElements[0].Value
    $bashCompletion = ". /usr/share/bash-completion/bash_completion 2> /dev/null"
    $commandCompletion = ". /usr/share/bash-completion/completions/$command 2> /dev/null"
    $COMPINPUT = "COMP_LINE=$COMP_LINE; COMP_WORDS=$COMP_WORDS; COMP_CWORD=$COMP_CWORD; COMP_POINT=$cursorPosition"
    $COMPGEN = "bind `"set completion-ignore-case on`" 2> /dev/null; $F `"$command`" `"$wordToComplete`" `"$previousWord`" 2> /dev/null"
    $COMPREPLY = "IFS=`$'\n'; echo `"`${COMPREPLY[*]}`""
    $commandLine = "$bashCompletion; $commandCompletion; $COMPINPUT; $COMPGEN; $COMPREPLY" -split ' '

    # Invoke bash completion and return CompletionResults.
    $previousCompletionText = ""
    (wsl.exe $commandLine) -split '\n' |
    Sort-Object -Unique -CaseSensitive |
    ForEach-Object {
        if ($wordToComplete -match "(.*=).*") {
            $completionText = Format-WslArgument ($Matches[1] + $_) $true
            $listItemText = $_
        } else {
            $completionText = Format-WslArgument $_ $true
            $listItemText = $completionText
        }

        if ($completionText -eq $previousCompletionText) {
            # Differentiate completions that differ only by case otherwise PowerShell will view them as duplicate.
            $listItemText += ' '
        }

        $previousCompletionText = $completionText
        [System.Management.Automation.CompletionResult]::new($completionText, $listItemText, 'ParameterName', $completionText)
    }
}

# Helper function to escape characters in arguments passed to WSL that would otherwise be misinterpreted.
function global:Format-WslArgument([string]$arg, [bool]$interactive) {
    if ($interactive -and $arg.Contains(" ")) {
        return "'$arg'"
    } else {
        return ($arg -replace " ", "\ ") -replace "([()|])", ('\$1', '`$1')[$interactive]
    }
}
