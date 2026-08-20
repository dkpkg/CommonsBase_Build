-- Test: ./dk0 --dangerously-trust-all --trust-local-package CommonsBase_Build -- dialog CommonsBase_Build.Toolchain.Discover.MSVC@1.0.0
--
-- The dk0 dialog uirule for MSVC toolchain discovery. It materializes the
-- probe and the packaged vswhere, captures the probe (which reads
-- toolchains.jsonc, runs vswhere + vcvarsall and emits KEY=VALUE), and writes
-- the full environment plus a staleness fingerprint into
-- etc/dk/t/resolved.jsonc (compare-and-swap) so build tasks consume the cache
-- and skip vcvarsall.
--
-- DRAFT limitations (tracked in dksdk-coder plans/toolchain/OPEN-ITEMS.md):
-- resolves the Windows_x86_64 entry only and overwrites resolved.jsonc rather
-- than merging other ABIs; $(...) expression values in toolchains.jsonc are
-- not yet substituted before the probe runs.
local M = { id = "CommonsBase_Build.Toolchain.Discover@1.0.0" }
_rules, uirules = build.newrules(M)

-- lua-ml has no local functions; helpers are globals with a package prefix.
-- lua-ml does not implement string.gsub, so escape char-by-char.
-- Escape a JSON string value: backslash and double quote.
function CommonsBase_Build__Discover_jsonesc(s)
    local out = ""
    local i = 1
    local n = string.len(s)
    while i <= n do
        local c = string.sub(s, i, i)
        if c == "\\" then
            out = out .. "\\\\"
        elseif c == "\"" then
            out = out .. "\\\""
        else
            out = out .. c
        end
        i = i + 1
    end
    return out
end

-- Parse KEY=VALUE lines from text into the table out.
function CommonsBase_Build__Discover_parsekv(text, out)
    local pos = 1
    local n = string.len(text)
    while pos <= n do
        local nl = string.find(text, "\n", pos)
        local stop
        if nl == nil then stop = n + 1 else stop = nl end
        local line = string.sub(text, pos, stop - 1)
        pos = stop + 1
        local ll = string.len(line)
        if ll > 0 and string.sub(line, ll, ll) == "\r" then
            line = string.sub(line, 1, ll - 1)
            ll = ll - 1
        end
        local eq = string.find(line, "=", 1)
        if eq ~= nil and eq > 1 then
            out[string.sub(line, 1, eq - 1)] = string.sub(line, eq + 1)
        end
    end
end

-- Return "  \"key\": \"escaped\",\n" when kv[key] is set, else "".
function CommonsBase_Build__Discover_field(kv, key)
    local v = kv[key]
    if v == nil then return "" end
    return "    \"" .. key .. "\": \"" .. CommonsBase_Build__Discover_jsonesc(v) .. "\",\n"
end

function uirules.MSVC(command, request, continue_)
    if command ~= "submit" then return end
    if continue_ == "start" then
        return {
            submit = {
                expressions = {
                    strings = {
                        probe = "$(--path=absnative get-object CommonsBase_Build.Toolchain.Discover.MSVC@1.0.0 -s Release.execution_abi -e 'bin/*' -d :)${/}bin${/}discover.bat",
                        vswhere = "$(--path=absnative get-object CommonsBase_Build.VSWhere@3.1.7 -s Release.execution_abi -e bin/vswhere.exe -d :)${/}bin${/}vswhere.exe"
                    }
                },
                andthen = { continue_ = { state = "captured" } }
            }
        }
    end
    if continue_ == "captured" then
        local abi = "Windows_x86_64"
        local r, msg, kind = request.ui.capture {
            program = request.continued.probe,
            args = { "--abi", abi },
            envmods = { "+VSWHERE=" .. request.continued.vswhere }
        }
        if r == nil then
            printf("dk toolchain dialog: probe was not run: %s\n", tostring(msg))
            request.io.flush()
            return { submit = {} }
        end
        if r.status ~= "exit" or r.code ~= 0 then
            printf("dk toolchain dialog: probe failed (status=%s code=%s):\n%s\n",
                tostring(r.status), tostring(r.code), r.stderr)
            request.io.flush()
            return { submit = {} }
        end

        local kv = {}
        CommonsBase_Build__Discover_parsekv(r.stdout, kv)

        local fp = "VCToolsVersion=" .. (kv.VCToolsVersion or "")
            .. ";WindowsSDKVersion=" .. (kv.WindowsSDKVersion or "")
            .. ";VSCMD_VER=" .. (kv.VSCMD_VER or "")

        local body = "{\n"
            .. "  \"$schema\": \"https://diskuv.com/dk/schema/dk-toolchains-resolved-1.0.json\",\n"
            .. "  \"schema_version\": { \"major\": 1, \"minor\": 0 },\n"
            .. "  \"resolved\": {\n"
            .. "    \"" .. abi .. "\": {\n"
        body = body .. "    \"fingerprint\": \"" .. CommonsBase_Build__Discover_jsonesc(fp) .. "\",\n"
        body = body .. CommonsBase_Build__Discover_field(kv, "VSINSTALLDIR")
        body = body .. CommonsBase_Build__Discover_field(kv, "VCToolsVersion")
        body = body .. CommonsBase_Build__Discover_field(kv, "WindowsSDKVersion")
        body = body .. CommonsBase_Build__Discover_field(kv, "VSCMD_VER")
        body = body .. CommonsBase_Build__Discover_field(kv, "VisualStudioVersion")
        body = body .. CommonsBase_Build__Discover_field(kv, "INCLUDE")
        body = body .. CommonsBase_Build__Discover_field(kv, "LIB")
        body = body .. CommonsBase_Build__Discover_field(kv, "LIBPATH")
        -- last field carries no trailing comma
        body = body .. "    \"PATH\": \"" .. CommonsBase_Build__Discover_jsonesc(kv.PATH or "") .. "\"\n"
        body = body .. "    }\n  }\n}\n"

        local meta = request.ui.checksum { path = "etc/dk/t/resolved.jsonc" }
        local expected
        if meta == nil then expected = "false" else expected = meta.sha256 end
        local ok, p, sha = request.ui.writefile {
            path = "etc/dk/t/resolved.jsonc",
            content = body,
            expected_sha256 = expected
        }
        printf("dk toolchain dialog: resolved %s written=%s to %s\n",
            abi, tostring(ok), tostring(p))

        -- Sibling flat cache the probes read directly: the raw KEY=VALUE the
        -- probe emitted, plus a DK_TC_FINGERPRINT line. resolved.jsonc stays
        -- the human-inspectable form; this is what discover.bat/.sh consume.
        local cache_path = "etc/dk/t/resolved/" .. abi .. ".env"
        local cache_body = r.stdout .. "DK_TC_FINGERPRINT=" .. fp .. "\n"
        local cmeta = request.ui.checksum { path = cache_path }
        local cexp
        if cmeta == nil then cexp = "false" else cexp = cmeta.sha256 end
        local cok, cp, csha = request.ui.writefile {
            path = cache_path,
            content = cache_body,
            expected_sha256 = cexp
        }
        printf("dk toolchain dialog: cache %s written=%s to %s\n",
            abi, tostring(cok), tostring(cp))
        request.io.flush()
        return { submit = {} }
    end
end

return M
