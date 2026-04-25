# CommonsBase_Build

## Testing and updating distribution scripts

```sh
./dk0 update
./dk0 -nosysinc --verbose distribute CommonsBase_Build-dist-any --library 'CommonsBase_Build@2.5.999911122233' --actual-in-place dist-any.u
```

> [!IMPORTANT]
> Each operating system will update its own slot's object id in the response to `$ post-object CommonsBase_Build.CMake0.F_Build@...` in [dist-any.u/run.u](dist-any.u/run.u).
> The CI in [.github/workflows/distribute-2.5.yml](.github/workflows/distribute-2.5.yml) will need an object id for **Linux x86_64**. Run the CI job to find the object id, or run the above commands in a [Docker container](#using-docker-to-update-distribution-scripts).

## Using docker to update distribution scripts

```sh
rm -rf t # or in PowerShelll: del -Force -Recurse .\t\
docker run -v .:/work --workdir /work -it quay.io/pypa/manylinux_2_28_x86_64:2026.04.08-5 sh ./dk0 -nosysinc -v -v distribute CommonsBase_Build-dist-any --library CommonsBase_Build@2.5.999911122233 --actual-in-place dist-any.u
```

## Updating dk0 and dk0.cmd scripts

On Windows PowerShell (from the root of this repository):

```powershell
$ErrorActionPreference = "Stop"

$tmp = Join-Path $env:TEMP ("dk-" + [guid]::NewGuid().ToString())
git clone --depth 1 https://github.com/diskuv/dk.git $tmp

Copy-Item (Join-Path $tmp "dk0") -Destination ".\dk0" -Force
Copy-Item (Join-Path $tmp "dk0.cmd") -Destination ".\dk0.cmd" -Force

$dkVer = (Select-String -Path (Join-Path $tmp "dk0.cmd") -Pattern 'SET DK_VER=(.+)').Matches[0].Groups[1].Value.Trim()

Remove-Item $tmp -Recurse -Force

git commit -m "dk0 $dkVer" -- .\dk0 .\dk0.cmd
```
