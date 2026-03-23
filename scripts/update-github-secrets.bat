@echo off
setlocal EnableDelayedExpansion

set "AWS_ENV_FILE=%~1"
set "DEPLOY_ENV_FILE=%~2"
if "%AWS_ENV_FILE%"=="" set "AWS_ENV_FILE=.env_git_aws"
if "%DEPLOY_ENV_FILE%"=="" set "DEPLOY_ENV_FILE=deploy/.env"

where gh >nul 2>nul
if errorlevel 1 goto gh_missing

set "REPO="
for /f "usebackq delims=" %%R in (`gh repo view --json nameWithOwner -q .nameWithOwner 2^>nul`) do set "REPO=%%R"
if "%REPO%"=="" goto repo_missing

if not exist "%DEPLOY_ENV_FILE%" goto deploy_env_missing

if not exist "%AWS_ENV_FILE%" (
  if exist ".env" (
    set "AWS_ENV_FILE=.env"
  ) else (
    set "AWS_ENV_FILE="
  )
)

set "MAX_RETRIES=5"

echo Updating DEPLOY_ENV_FILE for %REPO% from %DEPLOY_ENV_FILE%...
gh secret set DEPLOY_ENV_FILE -R "%REPO%" < "%DEPLOY_ENV_FILE%"
if errorlevel 1 goto gh_failed

set "SECRETS=AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY"

for %%K in (%SECRETS%) do (
  set "SECRET_VALUE="
  call :resolve_secret_value "%%K" SECRET_VALUE
  if "!SECRET_VALUE!"=="" (
    echo [error] %%K not found in .env_git_aws, .env, or the current shell environment.
    exit /b 1
  )
  if defined AWS_ENV_FILE (
    echo Updating %%K for %REPO% from %AWS_ENV_FILE%...
  ) else (
    echo Updating %%K for %REPO% from current shell environment...
  )
  call :set_secret_with_retry "%%K" "!SECRET_VALUE!"
  if errorlevel 1 goto gh_failed
)

set "REGION_VALUE="
call :resolve_secret_value "AWS_REGION" REGION_VALUE
if "!REGION_VALUE!"=="" (
  for /f "usebackq delims=" %%R in (`aws configure get region 2^>nul`) do (
    set "REGION_VALUE=%%R"
    goto region_found
  )
)
:region_found
if "!REGION_VALUE!"=="" (
  echo [error] AWS_REGION not found in .env_git_aws, .env, the current shell environment, or AWS CLI config.
  exit /b 1
)
echo Updating AWS_REGION for %REPO%...
call :set_secret_with_retry "AWS_REGION" "!REGION_VALUE!"
if errorlevel 1 goto gh_failed

echo Done.
exit /b 0

:deploy_env_missing
echo [error] %DEPLOY_ENV_FILE% not found in %cd%
exit /b 1

:gh_missing
echo [error] GitHub CLI (gh) not found. Install it and run "gh auth login".
exit /b 1

:repo_missing
echo [error] Could not detect repo via gh. Run "gh auth login" and retry.
exit /b 1

:gh_failed
echo [error] Failed to update secret.
exit /b 1

:set_secret_with_retry
set "SECRET_NAME=%~1"
set "SECRET_VALUE=%~2"

for /l %%I in (1,1,%MAX_RETRIES%) do (
  gh secret set "%SECRET_NAME%" -b "%SECRET_VALUE%" -R "%REPO%"
  if not errorlevel 1 exit /b 0
  echo [warn] Attempt %%I/%MAX_RETRIES% failed for %SECRET_NAME%.
  if %%I lss %MAX_RETRIES% timeout /t 5 /nobreak >nul
)

exit /b 1

:read_env_value
set "ENV_LOOKUP_KEY=%~1"
set "ENV_OUT_VAR=%~2"
set "%ENV_OUT_VAR%="
for /f "usebackq delims=" %%L in (`findstr /I /B "%ENV_LOOKUP_KEY%=" "%ENV_FILE%"`) do (
  for /f "tokens=1* delims==" %%A in ("%%L") do set "%ENV_OUT_VAR%=%%B"
  goto :eof
)
exit /b 0

:resolve_secret_value
set "SECRET_LOOKUP_KEY=%~1"
set "SECRET_OUT_VAR=%~2"
set "%SECRET_OUT_VAR%="

if defined %SECRET_LOOKUP_KEY% (
  call set "%SECRET_OUT_VAR%=%%%SECRET_LOOKUP_KEY%%%"
  exit /b 0
)

if defined AWS_ENV_FILE (
  set "ENV_FILE=%AWS_ENV_FILE%"
  call :read_env_value "%SECRET_LOOKUP_KEY%" "%SECRET_OUT_VAR%"
  if defined %SECRET_OUT_VAR% exit /b 0
)

if /I not "%AWS_ENV_FILE%"==".env" if exist ".env" (
  set "ENV_FILE=.env"
  call :read_env_value "%SECRET_LOOKUP_KEY%" "%SECRET_OUT_VAR%"
  if defined %SECRET_OUT_VAR% (
    set "AWS_ENV_FILE=.env"
    exit /b 0
  )
)

exit /b 0
