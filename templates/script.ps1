# TODO: describe this script
$ErrorActionPreference = 'Stop'

# Windows-specific setup goes here.

bash "$PSScriptRoot/<name>.sh" @args
exit $LASTEXITCODE
