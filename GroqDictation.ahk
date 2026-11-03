#Requires AutoHotkey v2.0
#SingleInstance Force
#MaxThreadsPerHotkey 1
InstallKeybdHook()

GroqKey := "gsk_REPLACE_WITH_YOUR_KEY"
UseProxy := false
ProxyURL := "http://proxy.example.com:8080"
ProxyUser := "YOUR_LOGIN"
ProxyPassword := "YOUR_PASSWORD"
; SOCKS5 example: socks5h://proxy.example.com:1080
Busy := false

^Space:: {
    global GroqKey, UseProxy, ProxyURL, ProxyUser, ProxyPassword, Busy
    if Busy
        return
    Busy := true
    opened := false
    base := A_Temp "\groq_" DllCall("GetCurrentProcessId") "_" A_TickCount
    wav := base ".wav"
    result := base ".txt"
    cfg := base ".cfg"
    try {
        key := Trim(GroqKey)
        if key = "" || key = "gsk_REPLACE_WITH_YOUR_KEY"
            throw Error("Insert your Groq API key at the top of this file.")
        if !RegExMatch(key, "^[A-Za-z0-9_-]+$")
            throw Error("Unexpected characters in API key.")
        curl := A_WinDir "\System32\curl.exe"
        if !FileExist(curl)
            throw Error("curl.exe was not found.")
        target := WinExist("A")
        MCI("open new type waveaudio alias GroqMic wait")
        opened := true
        MCI("set GroqMic time format milliseconds bitspersample 16 channels 1 samplespersec 16000 bytespersec 32000 alignment 2 wait")
        MCI("record GroqMic")
        started := A_TickCount
        ToolTip("Recording... Release Ctrl or Space to stop.")
        SoundBeep(1000, 70)
        while GetKeyState("Space", "P") && (GetKeyState("LCtrl", "P") || GetKeyState("RCtrl", "P")) {
            Sleep(10)
        }
        MCI("stop GroqMic wait")
        elapsed := A_TickCount - started
        MCI('save GroqMic "' wav '" wait')
        MCI("close GroqMic wait")
        opened := false
        if elapsed < 500 {
            ToolTip("Too short. Speak after the beep.")
            SetTimer(ClearTip, -2500)
            return
        }
        if !FileExist(wav) || FileGetSize(wav) < 3200
            throw Error("WAV is empty or too short. Check microphone and permissions.")
        ToolTip("Transcribing with Groq...")
        config := "silent`nshow-error`nfail-with-body`nconnect-timeout = 15`nmax-time = 90`n"
        config .= "url = " CQ("https://api.groq.com/openai/v1/audio/transcriptions") "`n"
        config .= "header = " CQ("Authorization: Bearer " key) "`n"
        config .= "form = " CQ('file=@"' wav '"') "`n"
        config .= "form = " CQ("model=whisper-large-v3-turbo") "`n"
        config .= "form = " CQ("language=ru") "`n"
        config .= "form = " CQ("response_format=text") "`n"
        config .= "output = " CQ(result) "`n"
        if UseProxy {
            if Trim(ProxyURL) = ""
                throw Error("ProxyURL is empty.")
            if InStr(ProxyUser, ":")
                throw Error("Proxy username must not contain a colon.")
            config .= "proxy = " CQ(ProxyURL) "`n"
            config .= "noproxy = " CQ("") "`n"
            if ProxyUser != "" || ProxyPassword != ""
                config .= "proxy-user = " CQ(ProxyUser ":" ProxyPassword) "`n"
            if RegExMatch(ProxyURL, "i)^https?://")
                config .= "proxy-anyauth`n"
        } else {
            config .= "proxy = " CQ("") "`n"
        }
        ; Temporary config contains credentials; never share it.
        FileAppend(config, cfg, "UTF-8-RAW")
        exitCode := RunWait('"' curl '" --disable --config "' cfg '"', , "Hide")
        if exitCode != 0 {
            details := FileExist(result) ? FileRead(result, "UTF-8") : "No response body. Check network and proxy settings."
            throw Error("Request failed. curl exit code: " exitCode "`n`n" SubStr(details, 1, 1200))
        }
        text := Trim(FileRead(result, "UTF-8"), " `t`r`n")
        if text = ""
            throw Error("Groq returned empty text.")
        KeyWait("Space")
        KeyWait("LCtrl")
        KeyWait("RCtrl")
        if !WinActive("ahk_id " target) {
            ToolTip()
            MsgBox("Active window changed. Text was NOT typed. Clipboard unchanged.`n`n" text, "Groq transcription")
            return
        }
        SendText(text)
        ToolTip("Done: text typed. Clipboard unchanged.")
        SetTimer(ClearTip, -2500)
    } catch as err {
        ToolTip()
        MsgBox(err.Message, "Groq dictation", "Iconx")
    } finally {
        if opened {
            try {
                MCI("close GroqMic wait")
            }
        }
        for path in [wav, result, cfg] {
            try {
                if FileExist(path)
                    FileDelete(path)
            }
        }
        Busy := false
    }
}

CQ(value) {
    if InStr(value, "`r") || InStr(value, "`n")
        throw Error("Settings must not contain line breaks.")
    return '"' StrReplace(StrReplace(value, '\', '\\'), '"', '\"') '"'
}

MCI(command) {
    code := DllCall("winmm.dll\mciSendStringW", "Str", command, "Ptr", 0, "UInt", 0, "Ptr", 0, "UInt")
    if code {
        buffer := Buffer(1024, 0)
        DllCall("winmm.dll\mciGetErrorStringW", "UInt", code, "Ptr", buffer.Ptr, "UInt", 512)
        throw Error("Audio recording error: " StrGet(buffer.Ptr, "UTF-16"))
    }
}

ClearTip() {
    ToolTip()
}
