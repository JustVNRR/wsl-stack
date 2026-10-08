@echo off
rem Stand-in for docker.exe, for testing what runs BEFORE a deployment:
rem build.ps1's preflight, build, create, export and rm. The export writes a
rem file that is not a tar, so the import that follows fails on purpose and the
rem run takes its failure path - the one that says what became of the packs.
if /i "%1"=="info" exit /b 0
if /i "%1"=="build" exit /b 0
if /i "%1"=="create" exit /b 0
if /i "%1"=="rm" exit /b 0
if /i "%1"=="rmi" exit /b 0
if /i "%1"=="export" (
    rem docker export -o <tar> <container>: the tar is the THIRD word, -o is
    rem the second. The file must not be a tar, or the run would go on to
    rem onboarding.
    echo not-a-tar > %3
    exit /b 0
)
exit /b 0
