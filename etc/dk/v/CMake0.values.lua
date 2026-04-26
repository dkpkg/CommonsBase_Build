local M = {
  id = "CommonsBase_Build.CMake0@3.25.3"
}

-- lua-ml does not support local functions.
-- And if the variable was "local" it would be nil inside the rules/uirules function bodies.
-- So a should-be-unique global is used instead.
CommonsBase_Build__CMake0__3_25_3 = {}

rules, uirules = build.newrules(M)

function CommonsBase_Build__CMake0__3_25_3.parse_common_args(request, p)
  p.gargs = request.user.gargs or {}
  p.bargs = request.user.bargs or {}
  p.iargs = request.user.iargs or {}
  p.overlayassetpath = request.user.overlayassetpath
  p.overlaybundlemodver = request.user.overlaybundlemodver
  p.sourcesubdir = assert(stringdk.sanitizesubpath(request.user.sourcesubdir or "."))
  p.out = request.user.out
  p.outexe = request.user.outexe
  assert(type(p.out) == "table" or type(p.outexe) == "table", "out or outexe must be a table. please provide `'out[]=FILE1' 'outexe[]=EXECUTABLE2' ...`")
  p.outrmexact = request.user.outrmexact or {}
  p.outrmglob = request.user.outrmglob or {}
  p.exe = request.user.exe or {}
  p.nstrip = request.user.nstrip or 0
end

function uirules.Build(command, request)
  local installdir = assert(request.user.installdir, "please provide 'installdir=INSTALL_DIRECTORY'")

  local src = request.user.src
  local mirrors = request.user.mirrors
  local urlpath = request.user.urlpath
  if src then
    assert(type(src) == "table",
      "src must be a table. please provide 'src[]=GLOB1' 'src[]=GLOB2' ...")
  else
    assert(mirrors and urlpath,
      "please provide either 'src[]=GLOB_PATTERN' or both 'mirrors[]=MIRROR_URL' and 'urlpath=URL_PATH'")
    assert(type(mirrors) == "table",
      "mirrors must be a table. please provide 'mirrors[]=MIRROR1' 'mirrors[]=MIRROR2' ...")

    -- validate mirrors are https:// or http://
    local k, v = next(mirrors)
    while k do
      local s, e = string.find(v, "^https?://")
      assert(s == 1, "mirror `" .. v .. "` must start with 'http://' or 'https://'")
      k, v = next(mirrors, k)
    end
  end

  -- parse arguments
  local p = {}
  CommonsBase_Build__CMake0__3_25_3.parse_common_args(request, p)

  -- split urlpath=path#sha256,size
  local urlpath_only, urlpath_sha256, urlpath_size
  if urlpath then
    local s1, e1 = string.find(urlpath, "#")
    assert(s1 and e1, "urlpath `" .. urlpath .. "` must be in the format path#sha256,size")
    urlpath_only = string.sub(urlpath, 1, s1 - 1)
    local s2, e2 = string.find(urlpath, ",", e1 + 1)
    assert(s2 and e2, "urlpath `" .. urlpath .. "` must be in the format path#sha256,size")
    urlpath_sha256 = string.sub(urlpath, e1 + 1, s2 - 1)
    urlpath_size = tonumber(string.sub(urlpath, e2 + 1))
  end

  p.outputid = "OurCMake_Build." .. request.rule.generatesymbol() .. "@1.0.0"
  p.src = src
  p.mirrors = mirrors
  p.urlpath_only = urlpath_only
  p.urlpath_sha256 = urlpath_sha256
  p.urlpath_size = urlpath_size
  p.installdir = installdir

  -- delegate to helper function since this is getting large
  return CommonsBase_Build__CMake0__3_25_3.ui_generate_build_install(command, request, p)
end

function CommonsBase_Build__CMake0__3_25_3.ui_generate_build_install(command, request, p)
  local k, v, a
  if command == "submit" then
    local bundle

    -- bundlemodver or assetmodver+assetpath
    local arg_content
    if p.src then
      -- source from local files; glob it and let .F_Build extract the bundle
      bundle = request.ui.glob {
        patterns = p.src, cell = "root"
      }
      local bundlemodver = assert(bundle.id, "could not determine bundle module version from src globs")
      arg_content = { "bundlemodver=" .. bundlemodver }
    else
      -- source from remote zipfile; create an asset bundle and let .F_Build extract the zipfile asset
      local genid = request.rule.generatesymbol()
      local origin = genid .. "-content"

      bundle = {
        id = "OurCMake_UI.Content." .. genid .. "@1.0.0",
        listing = {
          origins = {
            {
              name = origin,
              mirrors = p.mirrors
            }
          }
        },
        assets = {
          {
            origin = origin,
            path = p.urlpath_only,
            size = p.urlpath_size,
            checksum = {
              sha256 = p.urlpath_sha256
            }
          }
        }
      }
      arg_content = {
        "assetmodver=" .. bundle.id,
        "assetpath=" .. p.urlpath_only
      }
    end

    -- out
    local arg_out = {}
    local p_out = p.out or {}
    k, v = next(p_out)
    while k do
      a = "out[]=" .. v -- "out[]=FILE" is F_Build option
      arg_out[k] = a
      k, v = next(p_out, k)
    end

    -- outexe
    local arg_outexe = {}
    local p_outexe = p.outexe or {}
    k, v = next(p_outexe)
    while k do
      a = "outexe[]=" .. v -- "outexe[]=EXECUTABLE" is F_Build option
      arg_outexe[k] = a
      k, v = next(p_outexe, k)
    end

    -- outrmexact
    local arg_outrmexact = {}
    k, v = next(p.outrmexact)
    while k do
      a = "outrmexact[]=" .. v -- "outrmexact[]=GLOB_PATTERN" is F_Build option
      arg_outrmexact[k] = a
      k, v = next(p.outrmexact, k)
    end

    -- outrmglob
    local arg_outrmglob = {}
    k, v = next(p.outrmglob)
    while k do
      a = "outrmglob[]=" .. v -- "outrmglob[]=GLOB_PATTERN" is F_Build option
      arg_outrmglob[k] = a
      k, v = next(p.outrmglob, k)
    end

    -- exe
    local arg_exe = {}
    k, v = next(p.exe)
    while k do
      a = "-e" .. v -- "-e GLOB_PATTERN" is `post-object` option
      arg_exe[k] = a
      k, v = next(p.exe, k)
    end

    -- gargs
    local arg_gargs = {}
    k, v = next(p.gargs)
    while k do
      a = "gargs[]=" .. v -- "gargs[]=ARG" is F_Build option
      arg_gargs[k] = a
      k, v = next(p.gargs, k)
    end

    -- bargs
    local arg_bargs = {}
    k, v = next(p.bargs)
    while k do
      a = "bargs[]=" .. v -- "bargs[]=ARG" is F_Build option
      arg_bargs[k] = a
      k, v = next(p.bargs, k)
    end

    -- iargs
    local arg_iargs = {}
    k, v = next(p.iargs)
    while k do
      a = "iargs[]=" .. v -- "iargs[]=ARG" is F_Build option
      arg_iargs[k] = a
      k, v = next(p.iargs, k)
    end

    -- nstrip
    local arg_nstrip = {}
    if p.nstrip and p.nstrip > 0 then
      arg_nstrip = { "nstrip=" .. tostring(p.nstrip) } -- "nstrip=LEVELS" is F_Build option
    end

    -- concatenate [arg_out], [arg_outexe] and [arg_exe] into command
    local command = { "post-object", "CommonsBase_Build.CMake0.F_Build@3.25.3",
      "-d", p.installdir,
      "sourcesubdir=" .. p.sourcesubdir
    }
    table.move(arg_content, 1, table.getn(arg_content), table.getn(command) + 1, command) ---@diagnostic disable-line: deprecated, access-invisible
    table.move(arg_out, 1, table.getn(arg_out), table.getn(command) + 1, command) ---@diagnostic disable-line: deprecated, access-invisible
    table.move(arg_outexe, 1, table.getn(arg_outexe), table.getn(command) + 1, command) ---@diagnostic disable-line: deprecated, access-invisible
    table.move(arg_outrmexact, 1, table.getn(arg_outrmexact), table.getn(command) + 1, command) ---@diagnostic disable-line: deprecated, access-invisible
    table.move(arg_outrmglob, 1, table.getn(arg_outrmglob), table.getn(command) + 1, command) ---@diagnostic disable-line: deprecated, access-invisible
    table.move(arg_exe, 1, table.getn(arg_exe), table.getn(command) + 1, command) ---@diagnostic disable-line: deprecated, access-invisible
    table.move(arg_gargs, 1, table.getn(arg_gargs), table.getn(command) + 1, command) ---@diagnostic disable-line: deprecated, access-invisible
    table.move(arg_bargs, 1, table.getn(arg_bargs), table.getn(command) + 1, command) ---@diagnostic disable-line: deprecated, access-invisible
    table.move(arg_iargs, 1, table.getn(arg_iargs), table.getn(command) + 1, command) ---@diagnostic disable-line: deprecated, access-invisible
    table.move(arg_nstrip, 1, table.getn(arg_nstrip), table.getn(command) + 1, command) ---@diagnostic disable-line: deprecated, access-invisible

    -- print("Submitting command: " .. table.concat(command, " "))

    return {
      submit = {
        values = {
          schema_version = { major = 1, minor = 0 },
          bundles = { bundle }
        },
        commands = { command }
      }
    }
  elseif command == "ui" then
    print("done cmake build.")
  end
end

CommonsBase_Build__CMake0__3_25_3.execution_abis = {
  "Windows_x86_64", "Windows_x86", "Windows_arm64",
  "Linux_x86_64", "Linux_x86", "Linux_arm64",
  "Darwin_x86_64", "Darwin_arm64"
}

function CommonsBase_Build__CMake0__3_25_3.is_windows_abi(abi)
  return string.find(abi, "Windows_") ~= nil
end
function CommonsBase_Build__CMake0__3_25_3.is_unix_abi(abi)
  return string.find(abi, "Windows_") == nil
end

function CommonsBase_Build__CMake0__3_25_3.get_release_execution_abis()
  local abis = {}
  local k, v = next(CommonsBase_Build__CMake0__3_25_3.execution_abis)
  while k do
    abis[k] = "Release." .. v
    k, v = next(CommonsBase_Build__CMake0__3_25_3.execution_abis, k)
  end
  return abis
end
function CommonsBase_Build__CMake0__3_25_3.get_release_windows_execution_abis()
  local abis = {}
  local k, v = next(CommonsBase_Build__CMake0__3_25_3.execution_abis)
  while k do
    if CommonsBase_Build__CMake0__3_25_3.is_windows_abi(v) then
      abis[k] = "Release." .. v
    end
    k, v = next(CommonsBase_Build__CMake0__3_25_3.execution_abis, k)
  end
  return abis
end
function CommonsBase_Build__CMake0__3_25_3.get_release_unix_execution_abis()
  local abis = {}
  local k, v = next(CommonsBase_Build__CMake0__3_25_3.execution_abis)
  while k do
    if CommonsBase_Build__CMake0__3_25_3.is_unix_abi(v) then
      abis[k] = "Release." .. v
    end
    k, v = next(CommonsBase_Build__CMake0__3_25_3.execution_abis, k)
  end
  return abis
end

function rules.F_Build(command, request)
  if command == "declareoutput" then
    local slots = CommonsBase_Build__CMake0__3_25_3.get_release_execution_abis()
    return {
      declareoutput = {
        return_objects = {
          id = "OurCMake_F_Build." .. request.rule.generatesymbol() .. "@1.0.0",
          slots = slots,
          execution_slot = "Release.execution_abi"
        }
      }
    }
  elseif command == "submit" then
    -- parse arguments
    local p = {}
    CommonsBase_Build__CMake0__3_25_3.parse_common_args(request, p)

    p.outputid = request.submit.outputid
    p.bundlemodver = request.user.bundlemodver
    p.assetmodver = request.user.assetmodver
    p.assetpath = request.user.assetpath
    assert(p.bundlemodver or p.assetmodver,
      "please provide either 'bundlemodver=BUNDLEMODULE@VERSION' or 'assetmodver=ASSETMODULE@VERSION' for the CMake source directory")
    if p.assetmodver then
      assert(p.assetpath, "please provide 'assetpath=PATH_INSIDE_ASSET' when using 'assetmodver=ASSETMODULE@VERSION'")
    end

    p.coreutilsexe = "$(get-object CommonsBase_Std.Coreutils@0.2.2 -s ${SLOTNAME.Release.execution_abi} -m ./coreutils.exe -e '*' -f coreutils.exe)"
    p.fdexe = "$(get-object CommonsBase_Std.Fd@10.3.0 -s ${SLOTNAME.Release.execution_abi} -m ./fd.exe -e '*' -f fd.exe)"

    -- ninjaexe must be absolute path since it is passed to CMAKE_MAKE_PROGRAM CACHE variable
    -- use ninja.exe on Windows as the executable filename so it runs on Windows. but keep as `ninja` on Unix so CMake scripts are not confused
    p.absninjaexe_win32 = "$(--path=absnative get-object CommonsBase_Build.Ninja0@1.12.1 -s ${SLOTNAME.Release.execution_abi} -m ./ninja.exe -f ninja.exe -e '*')"
    p.absninjaexe_unix = "$(--path=absnative get-object CommonsBase_Build.Ninja0@1.12.1 -s ${SLOTNAME.Release.execution_abi} -m ./ninja.exe -f ninja -e '*')"

    local str_cmakezipname = "$(get-asset CommonsBase_Build.Apparatus.LookupCMake3_25_3@0.1.0 -p lookup-cmake-3-25-3 -m ./${SLOTNAME.execution_abi}.txt)" -- "cmake-3.25.3-windows-x86_64.zip" --
    local str_cmakebin = "$(get-asset CommonsBase_Build.Apparatus.LookupCMakeBin@0.1.0 -p lookup-cmake-bin -m ./${SLOTNAME.execution_abi}.txt)" -- "bin" --
    local abspath_cmakedir = "$(--path=absnative get-asset CommonsBase_Build.CMake0.Bundle@3.25.3 -p " .. str_cmakezipname .. " -n 1 -d : -e 'bin/*' -e 'CMake.app/Contents/bin/*')"
    p.cmakebin = abspath_cmakedir .. "${/}" .. str_cmakebin
    p.cmakeexe = p.cmakebin .. "${/}cmake${.exe.execution}"
    return CommonsBase_Build__CMake0__3_25_3.free_generate_build_install(request, p)
  end
end

function CommonsBase_Build__CMake0__3_25_3.free_generate_build_install(request, p)
  local k, v

  -- the source directory will be "s/" inside the function directory
  -- the build directory will be "b/" inside the function directory
  local sourcedir
  if p.sourcesubdir == "." or p.sourcesubdir == "./" then
    sourcedir = "s"
  else
    sourcedir = stringdk.quote_value_shell("s/" .. p.sourcesubdir)
  end

  -- precommands to get source and maybe overlay
  local precommand_getsource
  if p.bundlemodver then
    precommand_getsource = "get-bundle " .. p.bundlemodver .. " -d s"
  else
    precommand_getsource = "get-asset " .. p.assetmodver .. " -p " .. p.assetpath .. " -d s"
  end
  if p.nstrip and p.nstrip > 0 then
    precommand_getsource = precommand_getsource .. " -n " .. tostring(p.nstrip)
  end
  local precommands_private = {
    precommand_getsource
  }
  if p.overlaybundlemodver then
    table.insert(precommands_private, "get-bundle " .. p.overlaybundlemodver .. " -d t/s")
  elseif p.overlayassetpath and p.assetmodver then
    table.insert(precommands_private, "get-asset " .. p.assetmodver .. " -p " .. p.overlayassetpath .. " -d t/s")
  end

  -- start the true commands (not the precommands)
  local commands = {}

  -- run: cmake -G
  -- for each ABI, add the ABI-specific generator args to "commands" array.
  local abis = CommonsBase_Build__CMake0__3_25_3.get_release_execution_abis()
  k, v = next(abis)
  while k do
    local abi = v

    -- where is ninja
    local absninjaexe
    if CommonsBase_Build__CMake0__3_25_3.is_windows_abi(abi) then
      absninjaexe = p.absninjaexe_win32
    else
      absninjaexe = p.absninjaexe_unix
    end

    -- ninja generator args
    local gninjaargs = {}
    local generator
    if request.user.generator then
      generator = request.user.generator
    elseif CommonsBase_Build__CMake0__3_25_3.is_windows_abi(abi) then
      generator = "none"
    else
      generator = "Ninja"
      -- CMAKE_MAKE_PROGRAM needs to be absolute path
      gninjaargs = {
        "-DCMAKE_MAKE_PROGRAM:FILEPATH=" .. absninjaexe
      }
    end

    -- concatenate [p.gargs] into array "gargs". add to "commands" array
    local gargs = {
      p.cmakeexe, "-S", sourcedir, "-B", "b",
      -- CMAKE_INSTALL_PREFIX needs to be absolute path
      "-DCMAKE_INSTALL_PREFIX:FILEPATH=${SLOTABS." .. abi .. "}"
    }
    if generator ~= "none" then
      table.insert(gargs, "-G")
      table.insert(gargs, generator)
    end
    table.move(p.gargs, 1, table.getn(p.gargs), table.getn(gargs) + 1, gargs) ---@diagnostic disable-line: deprecated, access-invisible
    table.move(gninjaargs, 1, table.getn(gninjaargs), table.getn(gargs) + 1, gargs) ---@diagnostic disable-line: deprecated, access-invisible

    table.insert(commands, gargs)

    k, v = next(abis, k)
  end

    -- run: cmake --build
  -- concatenate p.bargs into array "bargs". add to "commands" array
  local bargs = {
    p.cmakeexe, "--build", "b"
  }
  table.move(p.bargs, 1, table.getn(p.bargs), table.getn(bargs) + 1, bargs) ---@diagnostic disable-line: deprecated, access-invisible
  table.insert(commands, bargs)
  
    -- run: cmake --install
  -- concatenate p.iargs into array "iargs". add to "commands" array
  local iargs = {
    p.cmakeexe, "--install", "b",
    -- the install prefix needs to be absolute path
    "--prefix", "${SLOTABS.Release.execution_abi}"
  }
  table.move(p.iargs, 1, table.getn(p.iargs), table.getn(iargs) + 1, iargs) ---@diagnostic disable-line: deprecated, access-invisible
  table.insert(commands, iargs)

  -- add build and install commands to "commands" array
  table.insert(commands, gargs)
  
  -- prepend overlay bundle copy command
  if p.overlaybundlemodver or p.overlayassetpath then
    local overlaycopycmd = {
      -- copy contents of t/s into s/
      p.coreutilsexe, "cp", "-v", "-r", "--target-directory", ".", "t/s"
    }
    table.insert(commands, 1, overlaycopycmd)
  end

  -- validate and add `rm -rf DIRS` for each ${SLOT.Release.execution_abi}/DIR in p.outrmexact
  local rmdirs = {}
  k, v = next(p.outrmexact)
  while k do
    v = assert(stringdk.sanitizesubpath(v)) -- sanitize to prevent malicious input
    rmdirs[k] = "${SLOT.Release.execution_abi}/" .. v
    k, v = next(p.outrmexact, k)
  end
  if (table.getn(rmdirs) > 0) then ---@diagnostic disable-line: deprecated, access-invisible
    local rmrfcmd = { p.coreutilsexe, "rm", "-rf" }
    table.move(rmdirs, 1, table.getn(rmdirs), table.getn(rmrfcmd) + 1, rmrfcmd) ---@diagnostic disable-line: deprecated, access-invisible
    local rmrfcmd1 = { rmrfcmd } -- add one [rm -rf] command
    table.move(rmrfcmd1, 1, table.getn(rmrfcmd1), table.getn(commands) + 1, commands) ---@diagnostic disable-line: deprecated, access-invisible
  end

  -- add `fd --glob --hidden --no-ignore -X coreutils rm -f \; -- GLOB ${SLOT.Release.execution_abi}` for each GLOB in p.outrmglob
  -- validation? the GLOB is after `--` so dashes won't be interpreted as options.
  -- also, the GLOB is applied to filenames _under_ the -C BASEDIR.
  -- so GLOB is sanitized
  -- --base-directory? it is hidden option; confer https://github.com/sharkdp/fd/issues/475
  k, v = next(p.outrmglob)
  while k do
    local fdcmd = { p.fdexe, "--glob", "--hidden", "--no-ignore",
      -- remove every file type except directories which should use outrmexact for safety
      "--type", "f", "--type", "l", "--type", "s", "--type", "p", "--type", "c", "--type", "b",
      "-X", p.coreutilsexe, "rm", "-f", ";",
      "--", v, "${SLOT.Release.execution_abi}" }
    local fdcmd1 = { fdcmd } -- add one [fd] command
    table.move(fdcmd1, 1, table.getn(fdcmd1), table.getn(commands) + 1, commands) ---@diagnostic disable-line: deprecated, access-invisible
    k, v = next(p.outrmglob, k)
  end

  -- output paths
  --   the union of p.out and p.outexe but p.outexe has .exe suffix on Windows
  local outpathscommon = {}
  local outpathswindows = {}
  local outpathsunix = {}
  local p_out = p.out or {}
  local p_outexe = p.outexe or {}
  k, v = next(p_out)
  while k do
    outpathscommon[k] = v
    k, v = next(p_out, k)
  end
  k, v = next(p_outexe)
  while k do
    outpathswindows[k] = v .. ".exe"
    outpathsunix[k] = v
    k, v = next(p_outexe, k)
  end

  -- output assets
  --   only add [outpathscommon] if non-empty
  --   ditto for [outpathswindows] and [outpathsunix].
  local outassets = {}
  if next(outpathscommon) then
    table.insert(outassets, {
      slots = CommonsBase_Build__CMake0__3_25_3.get_release_execution_abis(),
      paths = outpathscommon
    })
  end
  if next(outpathswindows) then    
    table.insert(outassets, {
      slots = CommonsBase_Build__CMake0__3_25_3.get_release_windows_execution_abis(),
      paths = outpathswindows
    })
  end
  if next(outpathsunix) then
    table.insert(outassets, {
      slots = CommonsBase_Build__CMake0__3_25_3.get_release_unix_execution_abis(),
      paths = outpathsunix
    })
  end

  return {
    submit = {
      values = {
        schema_version = { major = 1, minor = 0 },
        forms = {
          {
            id = p.outputid,
            precommands = {
              private = precommands_private
            },
            function_ = {
              commands = commands,
              envmods = {
                -- p.cmakebin: to mitigate "Could not find CMAKE_ROOT", cmake must be on PATH for Ubuntu 24.04.
                -- https://gitlab.kitware.com/cmake/cmake/-/work_items/22280#note_967101    
                "<PATH=" .. p.cmakebin
              }
            },
            outputs = {
              assets = outassets
            }
          }
        }
      }
    }
  }
end

return M
