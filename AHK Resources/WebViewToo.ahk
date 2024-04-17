;///////////////////////////////////////////////////////////////////////////////////////////
; This is my first attempt at creating a class
; The goal of this class is to smash together 
; Thqby's WebView2.ahk library
; 	https://github.com/thqby/ahk2_lib/blob/master/WebView2/WebView2.ahk
; With G33k's Neutron.ahk library
; 	https://github.com/G33kDude/Neutron.ahk
;
; MIT License
;
; Permission is hereby granted, free of charge, to any person obtaining a copy
; of this software and associated documentation files (the "Software"), to deal
; in the Software without restriction, including without limitation the rights
; to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
; copies of the Software, and to permit persons to whom the Software is
; furnished to do so, subject to the following conditions:
;
; The above copyright notice and this permission notice shall be included in all
; copies or substantial portions of the Software.
;
; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
; IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
; FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
; AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
; LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
; OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
; SOFTWARE.
;
;-------------------------------------------------------------------------------------------
;
;	v0.1
;		Based Features Created and working
;		METHODS:
;           WebviewWindow.Load(filename)
;           WebviewWindow.Show(options, title) ;neither parameter required
;           WebviewWindow.Hide()
;           WebviewWindow.Destroy()
;           WebviewWindow.Debug() ; Opens DevTools for Edge
;           WebviewWindow.Opt(options) ; Used to assign GUI options to the WebviewWindow
;           WebviewWindow.closeWV()
;           WebviewWindow.minimizeWV()
;           WebviewWindow.maximizeWV()
;           WebviewWindow.qp(script) ;Shorthand to get information from webpage, can be used for variable declaration
;           WebviewWindow.QueryPage(script, varRef, callbackFunc)
;           WebviewWindow.printToPdf(Filename, orientation) ;shorthand method for printToPdf, you will be asked to choose the directory to save the file to and if you do not supply a filename you will be asked to input one
;           WebviewWindow.GetFormData(formElement)
;           static WebviewWindow.forEach(obj) ;Used to enumerate information from event handlers
;
;
;		Example of in-line onclick to call an AHK function
;			onclick="(async function(){obj = await window.chrome.webview.hostObjects.[objectName];obj.func((await [obj.paramater]));})();"
;
;	Current Project Hangups:
;		Need to figure out if I can use the Webview2Loader.dll that has been included as a resource instead of extracting it
;		Need to figure out how I want to handle pages and other resources that have been included into a compiled .exe
;			As of right now, I have been unable to find a way to load a webpage from an included resource without it breaking things
;			Need to look at the methods to tweak: Load(), LoadFromResource(), CreateTempFile()
;///////////////////////////////////////////////////////////////////////////////////////////

#Requires Autohotkey v2+
#Include WebView2.ahk
class WebviewWindow {
	static TEMPLATE := {}
	static TEMPLATE.CODE := "
	(
		<!DOCTYPE html>
		<html>
			<head>
				<meta http-equiv='X-UA-Compatible' content='IE=edge'>
				<style>
					html, body {
						width: 100%; height: 100%;
						margin: 0; padding: 0;
						font-family: sans-serif;
					}

					body {
						display: flex;
						flex-direction: column;
					}

					header {
						width: 100%;
						display: flex;
						background: silver;
						font-family: Segoe UI;
						font-size: 9pt;
					}

					.title-bar {
						padding: 0.35em 0.5em;
						flex-grow: 1;
					}

					.title-btn {
						padding: 0.35em 1.0em;
						cursor: pointer;
						vertical-align: bottom;
						font-family: Webdings;
						font-size: 11pt;
					}

					body .title-btn-restore {
						display: none
					}

					body.neutron-maximized .title-btn-restore {
						display: block
					}

					body.neutron-maximized .title-btn-maximize {
						display: none
					}

					.title-btn:hover {
						background: rgba(0, 0, 0, .2);
					}

					.title-btn-close:hover {
						background: #dc3545;
					}

					.main {
						flex-grow: 1;
						padding: 0.5em;
						overflow: auto;
					}
				</style>
				
				<style id="customCSS"></style>
			</head>

			<body>

				<div class='main' id="customHTML"><a href='https://www.google.com'>Google!</a></div>
				
				<script id="customJS"></script>
				
			</body>
		</html>
	)"
	
	static TEMPLATE.NAME := "Template.html"
	static UniqueID := WebviewWindow.CreateUniqueID()
	static CreateUniqueID() {
		SplitPath(A_ScriptName,,,, &OutNameNoExt)
		Loop Parse, OutNameNoExt {
			id .= Mod(A_Index, 3) ? Format("{:X}", Ord(A_LoopField)) : "-" Format("{:X}", Ord(A_LoopField))
		}
		return RTrim(StrLower(id), "-")
	}
	static TempDir := A_Temp "\" WebviewWindow.UniqueID
	static DllName := "WebView2Loader_" (A_PtrSize * 8) ".dll"

	;Set Default Values as fallbacks
	;gui := unset ;The underlying GUI Object representing the window
	bound := {} ;Bound functions with circular references that must be freed before the class can be successfully garbage collected
	wvc := "" ;Prevents 'variable unset' error
	wv := "" ;Prevents 'variable unset' error
	nwr := "" ;Prevenets 'variable unset' error
	width := (A_ScreenWidth / 2) ;Base width if not provided
	height := (A_ScreenHeight / 2) ;Base height if not provided
	
	;Windows Messages
	WM_DESTROY => 0x02
	WM_SIZE => 0x05
	WM_NCCALCSIZE => 0x83
	WM_NCHITTEST => 0x84
	WM_NCLBUTTONDOWN => 0xA1
	WM_KEYDOWN => 0x100
	WM_KEYUP => 0x101
	WM_SYSKEYDOWN => 0x104
	WM_SYSKEYUP => 0x105
	WM_MOUSEMOVE => 0x200
	WM_LBUTTONDOWN => 0x201
	LISTENERS := [this.WM_DESTROY, this.WM_SIZE, this.WM_NCCALCSIZE, this.WM_KEYDOWN, this.WM_KEYUP, this.WM_SYSKEYDOWN, this.WM_SYSKEYUP, this.WM_LBUTTONDOWN]
	
	;formData := "" ;Commented Out to see if needed

	/**
	* The count of pixels inset from the window edge that the sizing handles to
	* resize the window will appear for.
	**/
	;border_size := 6 ;Used in _WindowProc

	;modifiers := 0 ;Used in _OnMessage

	/* Used in _OnMessage
	;Shortcuts to prevent the web page from processing 
	disabled_shortcuts := Map(
		; No modifiers
		0, Map(
			this.VK_F5, true	; Refresh page
		),
		; Ctrl
		this.MODIFIER_BITMAP[this.VK_CONTROL], Map(
			GetKeyVK("F"), true,	; Ctrl+F find
			GetKeyVK("L"), true,	; Ctrl+L focus location bar
			GetKeyVK("N"), true,	; Ctrl+N open new tab
			GetKeyVK("O"), true,	; Ctrl+O open file
			GetKeyVK("P"), true,	; Ctrl+P print page
		)
	)
	*/
	
	
	
	__New(html := "", css := "", js := "") {
		;EnvSet("WEBVIEW2_DEFAULT_BACKGROUND_COLOR", "0xFF006600") ;Can use this to set the default backgroundColor for the WebView2
		this.gui := Gui("+Resize +Caption +ToolWindow")
		this.gui.BackColor := "000000"
		this.gui.Show("x-10000 y-10000 w" (A_ScreenWidth / 2) " h" (A_ScreenHeight / 2)) ;I can't seem to attach the WebView2 to the GUI unless it is visible on the screen
		this.wvc := !A_IsCompiled ? WebView2.create(this.gui.Hwnd) : WebView2.create(this.gui.Hwnd,,,,,, WebviewWindow.DllName)
		this.wv := this.wvc.CoreWebView2
		this.wv.NavigateToString(WebviewWindow.TEMPLATE.CODE)
		if (html != "" || css != "" || js != "") {
			this.wv.ExecuteScript("document.getElementById('customHTML').innerHTML = '" html "';", 0)
			this.wv.ExecuteScript("document.getElementById('customJS').innerHTML = '" js "';", 0)
			this.wv.ExecuteScript("document.getElementById('customCSS').innerHTML = '" css "';", 0)
		}
		this.gui.OnEvent("Size", (*) => this.Fill())
		this.Hide()
		this.gui.Opt("-ToolWindow")
		if (!DirExist(WebviewWindow.TempDir)) {
			DirCreate(WebviewWindow.TempDir)
		}
	}

	;-------------------------------------------------------------------------------------------
	
	Load(Filename) {
		if (InStr(Filename, "https://")) {
			Url := Filename
		}
		else {
			if (A_IsCompiled) {
				WebviewWindow.CreateFileFromResource(Filename)	
				Url := WebviewWindow.TempDir "\" Filename
			}
			else {
				Url := A_WorkingDir "\" Filename
			}
		}
		this.Navigate(Url)
		return this
	}

	static CreateFileFromResource(ResourceName) {
		Module := DllCall("GetModuleHandle", "Ptr", 0, "Ptr")
		Resource := DllCall("FindResource", "Ptr", Module, "Str", ResourceName, "UInt", RT_RCDATA := 10, "Ptr")
		ResourceSize := DllCall("SizeofResource", "Ptr", Module, "Ptr", Resource)
		ResourceData := DllCall("LoadResource", "Ptr", Module, "Ptr", Resource, "Ptr")
		ConvertedData := DllCall( "LockResource", "Ptr", ResourceData, "Ptr")
		TextData := StrGet(ConvertedData, ResourceSize, "UTF-8")

		SplitPath(ResourceName, &OutFileName, &OutDir)
		if (!DirExist(WebviewWindow.TempDir "\" OutDir)) {
			DirCreate(WebviewWindow.TempDir "\" OutDir)
		}
		if (!FileExist(WebviewWindow.TempDir "\" ResourceName) || TextData != FileRead(WebviewWindow.TempDir "\" ResourceName)) {
			try FileDelete(WebviewWindow.TempDir "\" ResourceName)
			TempFile := FileOpen(WebviewWindow.TempDir "\" ResourceName, "w")
			TempFile.Write(TextData)
			TempFile.Close()
		}
		FileSetAttrib("+HR", WebviewWindow.TempDir "\" OutDir)
		FileSetAttrib("+HR", WebviewWindow.TempDir "\" ResourceName)

		StartingPos := 1
		LinkedFileArray := []
		while (RegExMatch(TextData, '<script.*?src="(?!https)(.*?)">', &Match, StartingPos) || RegExMatch(TextData, '<link.*?href="(?!https)(.*?)" rel="stylesheet">', &Match, StartingPos)) {
			LinkedFileArray.Push(Match[1])
			StartingPos += StrLen(Match[])
		}
		for k, v in LinkedFileArray {
			WebviewWindow.CreateFileFromResource(OutDir "\" StrReplace(v, "/", "\"))
		}
	}

	;-------------------------------------------------------------------------------------------
	
	Show(options := "", title := this.title) {
		width := RegExMatch(options, "w\s*\K\d+", &match) ? match[] : this.width
		height := RegExMatch(options, "h\s*\K\d+", &match) ? match[] : this.height

		; AutoHotkey sizes the window incorrectly, trying to account for borders
		; that aren't actually there. Call the function AHK uses to offset and
		; apply the change in reverse to get the actual wanted size.
		rect := Buffer(16, 0)
		DllCall("AdjustWindowRectEx",
			"Ptr", rect,	; LPRECT lpRect
			"UInt", 0x80CE0000,	; DWORD  dwStyle
			"UInt", 0,	; BOOL   bMenu
			"UInt", 0,	; DWORD  dwExStyle
			"UInt"	; BOOL
		)
		width += NumGet(rect, 0, "Int") - NumGet(rect, 8, "Int")
		height += NumGet(rect, 4, "Int") - NumGet(rect, 12, "Int")

		this.gui.title := title
		this.gui.Show(options " w" width " h" height)
		return this
	}
	
	;-------------------------------------------------------------------------------------------
	
	Close() {
		;this.wvc.Close() ;Close the WebView2Controller before closing the window
		WinClose("ahk_id" this.gui.hWnd)
		return this
	}

	;-------------------------------------------------------------------------------------------
	
	Debug() {
		this.OpenDevToolsWindow()
		this.ExecuteScript("DebugMode = 1;", 0)
		return this
	}
		
	;-------------------------------------------------------------------------------------------
		
	qp(script) {
		this.QueryPage(script, &queryResponse)
		while (!IsSet(queryResponse)) {
			Sleep(50)
		}
		return queryResponse
	}
	
	QueryPage(script, variable := "QueryPageVariablePlaceholder", callback := "QueryPageCallbackPlaceholder") {
		QueryPageResponseHandler(WebviewWindow, varName, Response) {
			%varName% := Response
		}
		static QueryPageResponsePlaceholder := "QueryPageResponsePlaceholder"
		if (variable = "QueryPageVariablePlaceholder") {
			variable := QueryPageResponsePlaceholder
			variable := &%variable%
		}
		if (callback = "QueryPageCallbackPlaceholder") {
			callback := QueryPageResponseHandler
		}
		script :=  RegExReplace(script, "'", "`""), script := RegExReplace(script, ".*\Kreturn ?", "output = ")
		try this.AddHostObjectToScript("QueryPage", {Webview:this, varName:variable, func:callback})
		this.ExecuteScript("(async function(){obj = window.chrome.webview.hostObjects.QueryPage;try{obj.script = eval('" script "');}catch(err){obj.script = 'There was an error';}if (typeof output !== 'undefined'){obj.script = output;}obj.func((await obj.Webview), (await obj.varName), (await obj.script));})();", 0)
		SetTimer((*) => this.RemoveQueryPageHostObject, -100)
	}
	
	RemoveQueryPageHostObject() {
		try	this.RemoveHostObjectFromScript("QueryPage")
	}

	;-------------------------------------------------------------------------------------------
	
	/*
	simplePrintToPdf(Filename := "", Orientation := "portrait") {
		;if (RegExMatch(Filename, "^[a-zA-Z]:\\", &match)) || (RegExMatch(Filename, "^\\\\", &match)) {} ;Checks to see if the Filename contains a Drive Letter or network path at the start
		OutputDir := DirSelect(, 3, "Select the Folder you'd like to save your PDF file to")
		if (OutputDir = "") {
			return (MsgBox("Print Canceled", "Print to PDF"))
		}
		if (Filename = "") {
			FilenameInput := InputBox("Please enter a name for your PDF: ", "Printing to PDF", "w210 h88")
			if (FilenameInput.Result != "OK") {
				return (MsgBox("Print Canceled", "Print to PDF"))
			}
			else {
				Filename := FilenameInput.Value
			}
		}
		if (FileExist(OutputDir "\" Filename ".pdf")) {
			if (MsgBox("The following file already exists, would you like to overwrite it?`n`n" OutputDir "\" Filename ".pdf", "Print to PDF",  4) = "No") {
				return (MsgBox("Print Canceled", "Print to PDF"))
			}
		}
		settings := this.wv.Environment.CreatePrintSettings()
		if (StrLower(Orientation) = "landscape") {
			settings.Orientation := WebView2.PRINT_ORIENTATION.LANDSCAPE
		}
		else {
			settings.Orientation := WebView2.PRINT_ORIENTATION.PORTRAIT
		}
		this.wv.PrintToPdf(OutputDir "\" Filename ".pdf", settings, WebView2.Handler(this.simplePrintToPdfHandler))
		Loop {
			if (FileExist(OutputDir "\" Filename ".pdf")) {
				if (MsgBox("Would you like to open this PDF?", "Print to PDF", 4) = "Yes") {
					Run(OutputDir "\" Filename ".pdf")
				}
				break
			}
			else {
				Sleep(100)
			}
		}
	}
	*/

	simplePrintToPdf(Orientation := "portrait") {
		Filename := FileSelect("S16",,, "*.pdf")
		if (Filename = "") {
			return (MsgBox("Print Canceled", "Print to PDF", "262144"))
		}

		Settings := this.Environment.CreatePrintSettings()
		if (StrLower(Orientation) = "landscape") {
			Settings.Orientation := WebView2.PRINT_ORIENTATION.LANDSCAPE
		}
		else {
			Settings.Orientation := WebView2.PRINT_ORIENTATION.PORTRAIT
		}
		this.PrintToPdf(Filename, Settings, WebView2.Handler(this.simplePrintToPdfHandler))
		if (MsgBox("Would you like to open this PDF?", "Print to PDF", "262148") = "Yes") {
			while (!FileExist(FileName)) {
				Sleep(50)
			}
			Run(FileName)
		}
	}

	simplePrintToPdfHandler(HandlerPtr, Success) {
		if (!Success) {
			MsgBox("An error occurred while attempting to PrintToPdf()", "Simple PrintToPdf", "262144")
		}
	}

	;-------------------------------------------------------------------------------------------

	GetFormData(formElement, useIdAsName := true) {
		script := "var form = document.getElementById('" formElement "');var elements = form.elements;var elementsArray = Array.from(elements);let text = '';elementsArray.forEach( function(item, index) { if ((item.type !== 'reset') && (item.type !== 'submit') && (item.type !== 'button')){text += '' + item.id + '<br>' + item.value + '<br>';}});var output = text;"
		this.QueryPage(script, &formData)
		while (!IsSet(formData)) { ; Wait for a response from the Webpage
			Sleep(50)
		}
		formDataArray := StrSplit(formData, "<br>")
		formData := Map(), keyCount := 1, valueCount := 2
		Loop(formDataArray.length / 2) {
			formData.Set(formDataArray[keyCount], formDataArray[valueCount])
			keyCount += 2, valueCount += 2
		}
		return formData
	}	

	;-------------------------------------------------------------------------------------------
	
	static CreateTempFile(Filename := WebviewWindow.TEMPLATE.NAME, Contents := WebviewWindow.TEMPLATE.CODE, Timeout := 10000) {
		Template := FileOpen(Filename, "w")
		Template.Write(Contents)
		Template.Close()
		SetTimer((*) => FileDelete(Filename), -Timeout)
	}
	
	;-------------------------------------------------------------------------------------------

	static DeleteInstalledFiles(FileArray) {
		for key, value in FileArray {
			try FileDelete(value)
		}
	}
	
	;-------------------------------------------------------------------------------------------
	
	static EncodeURI(Uri, RegEx := "[0-9A-Za-z]") {
		NumPut("Ptr", StrPut(Uri, "UTF-8"), output := Buffer(600, 0))
		StrPut(Uri, output, "UTF-8")
		While Code := NumGet(output, A_Index - 1, "UChar") {
			Res .= (Char := Chr(Code)) ~= RegEx ? Char : Format("%{:02X}", Code)
		}
		return Res
	}

	static DecodeURI(Uri, Encoding := "UTF-8") {
		while (StartingPos := RegExMatch(Uri, "i)(%[\da-f]{2})+", &match, StartingPos := 1) ? match.Pos : 0) {
			output := Buffer(StrLen(match[]) // 3, 0), Code := SubStr(match[], 2)
			Loop Parse, Code, "%" {
				NumPut("UChar", "0x" A_LoopField, output, A_Index - 1)
			}
			Decoded := StrGet(output, Encoding)
			Uri := SubStr(Uri, 1, StartingPos - 1) . Decoded . SubStr(Uri, StartingPos + StrLen(Code) + 1)
			StartingPos += StrLen(Decoded) + 1
		}
		return Uri
	}
	
	;-------------------------------------------------------------------------------------------
	
	static LoadFromResource(ResourceName) {
		if (!A_IsCompiled) {
			TextData := FileRead(ResourceName)
		}
		else {
			Module := DllCall("GetModuleHandle", "Ptr", 0, "Ptr")
			Resource := DllCall("FindResource", "Ptr", Module, "Str", ResourceName, "UInt", RT_RCDATA := 10, "Ptr")
			ResourceSize := DllCall("SizeofResource", "Ptr", Module, "Ptr", Resource)
			ResourceData := DllCall("LoadResource", "Ptr", Module, "Ptr", Resource, "Ptr")
			ConvertedData := DllCall( "LockResource", "Ptr", ResourceData, "Ptr")
			TextData := StrGet(ConvertedData, ResourceSize, "UTF-8")
			While (RegExMatch(TextData, '<script.*?src="(?!https)(.*?)">')) {
				MatchPos := RegExMatch(TextData, '<script.*?src="(.*?)">', &Match)
				if (MatchPos != 0) {
					MatchPos := RegExMatch(Match[], '"(.*?)"', &Url)
					if (MatchPos != 0) {
						ScriptUrl := Trim(Url[], "`"")
						ScriptText := WebviewWindow.LoadFromResource("Pages/" ScriptUrl)
						TextData := RegExReplace(TextData, '<script.*?src="(.*?)">', "<script>" ScriptText,, 1)
					}
				}
			}
			While (RegExMatch(TextData, '<link.*?href="(?!https)(.*?)" rel="stylesheet">')) {
				MatchPos := RegExMatch(TextData, '<link.*?href="(.*?)" rel="stylesheet">', &Match)
				if (MatchPos != 0) {
					MatchPos := RegExMatch(Match[], '"(.*?)"', &Url)
					if (MatchPos != 0) {
						ScriptUrl := Trim(Url[], "`"")
						ScriptText := WebviewWindow.LoadFromResource("Pages/" ScriptUrl)
						TextData := RegExReplace(TextData, '<link.*?href="(.*?)" rel="stylesheet">', "<style>" ScriptText "</style>",, 1)
					}
				}
			}
		}
		return TextData
	}
	
	;-------------------------------------------------------------------------------------------
	
	static forEach(Obj, Parent := "Default") {
		output := ""
		try {
			for k, v, in Obj {
				try {
					output .= Parent " >> " k ": " v "`n"
				}
				catch {
					output .= WebviewWindow.forEach(v, Parent " >> " k)
				}
			}
		}
		return output
	}

	static getParent(obj) {
		try {
			if (InStr(obj.Settings.UserAgent, "ParentID/")) {
				RegExMatch(obj.Settings.UserAgent, "\d+$", &match)
				output := match[]
				return output
			}
		}
	}

	;-------------------------------------------------------------------------------------------
	/**
	 * Makes text safe to be embedded in HTML
	 * Reference https://stackoverflow.com/a/6234804
	 * @param {String} unsafe An HTML-unsafe string
	 * @return {String} An HTML safe string
	**/
	static EscapeHTML(unsafe) {
		unsafe := StrReplace(unsafe, "&", "&amp;")
		unsafe := StrReplace(unsafe, "<", "&lt;")
		unsafe := StrReplace(unsafe, ">", "&gt;")
		unsafe := StrReplace(unsafe, '"', "&quot;")
		unsafe := StrReplace(unsafe, "'", "&#039;")
		return unsafe
	}

	/**
	 * Wrapper for Format that applies EscapeHTML to each value before passing
	 * them on. Useful for dynamic HTML generation.
	 * @param {String} formatStr The format string
	 * @param values...          The placeholder values
	 * @return {String} The formatted version of the specified string
	**/
	static FormatHTML(formatStr, values*) {
		for i, value in values {
			values[i] := WebviewWindow.EscapeHTML(value)
		}
		return Format(formatStr, values*)
	}

    ;-------------------------------------------------------------------------------------------
    ;Inherited GUI Methods
    Destroy() {
		this.gui.Destroy()
		return this
	}

    Flash(Blink?) {
		if (IsSet(Blink)) {
			this.gui.Flash(Blink)
		}
		else {
			this.gui.Flash
		}
	}

    GetClientPos(params*) => this.gui.GetClientPos(params*)
    GetPos(params*) => this.gui.GetPos(params*)

    Hide() {
		this.gui.Hide()
		return this
	}

    Maximize() {
		if DllCall("IsZoomed", "UPtr", this.gui.hWnd) {
			this.gui.Restore()
		} else {
			this.gui.Maximize()
		}
		this.Fill()
		return this
	}

    Minimize() {
		this.gui.Minimize()
		return this
	}

    Move(params*) => this.gui.Move(params*)

    OnEvent(eventName, callback, addRemove := unset) {
		this.gui.OnEvent(eventName, (p*) => (p[1] := this, callback(p*)), addRemove?)
		return this
	}

    Opt(options) {
		this.gui.Opt(options)
		return this
	}
    
    Restore() => this.gui.Restore()

    ;-------------------------------------------------------------------------------------------
    ;Inherited GUI Properties
    hWnd => this.HasProp("gui") ? this.gui.hWnd : ""

    MarginX {
		get => this.gui.MarginX
		set => this.gui.MarginX := Value
	}

    MarginY {
		get => this.gui.MarginY
		set => this.gui.MarginY := Value
	}

    MenuBar {
		get => this.gui.MenuBar
		set => this.gui.MenuBar := Value
	}

    Name {
		get => this.gui.Name
		set => this.gui.Name := Value
	}

    Title {
		get => this.gui.Title
		set => this.gui.Title := Value
	}


	;-------------------------------------------------------------------------------------------
	;Controller class assignments
	Fill() => this.wvc.Fill() ;Fills the available GUI space with the CoreWebView2Controller
	CoreWebView2 => this.wvc.CoreWebView2 ;Gets the CoreWebView2 associated with this CoreWebView2Controller
	IsVisible { ;Boolean => Determines whether to show or hide the WebView
		get => this.wvc.IsVisible
		set => this.wvc.IsVisible := Value
	}
	Bounds { ;Rectangle => Gets or sets the WebView bounds
		get => this.wvc.Bounds
		set => this.wvc.Bounds := Value
	}
	ZoomFactor { ;Double => Gets or sets the zoom factor for the WebView
		get => this.wvc.ZoomFactor
		set => this.wvc.ZoomFactor := Value
	}
	ParentWindow { ;Integer => Gets the parent window provided by the app or sets the parent window that this WebView is using to render content
		get => this.wvc.ParentWindow 
		set => this.wvc.ParentWindow := Value ;Not recommened to use set => because it dettaches the WebView2 window and can break the software
	}
	DefaultBackgroundColor { ;HexColorCode => Gets or sets the WebView default background color.
		get => this.wvc.DefaultBackgroundColor
		set => this.wvc.DefaultBackgroundColor := WebviewWindow.ConvertColor(Value)
	}
	static ConvertColor(BGRValue) { ;Converts provided HexColorCode from RGB to BGR for use with DefaultBackgroundColor
		BGRValue := String(BGRValue)
		if (IsXDigit(BGRValue)) && (!InStr(BGRValue, "0x")) {
			BGRValue := "0x" BGRValue
		}
		BlueByte := (BGRValue & 0xFF0000) >> 16
		GreenByte := BGRValue & 0x00FF00
		RedByte := (BGRValue & 0x0000FF) << 16
		return RedByte | GreenByte | BlueByte
	}

	/**
	 * RasterizationScale, ShouldDetectMonitorScaleChanges, and BoundsMode all work together
	 * If you want to use set => (RasterizationScale||ShouldDetectMonitorScaleChanges||BoundsMode)
	 * you will need to turn on DPI Awareness for your script by using the following DllCall
	 * DllCall("SetThreadDpiAwarenessContext", "ptr", -3, "ptr")
	**/
	RasterizationScale { ;Double => Gets or sets the WebView rasterization scale
		get => this.wvc.RasterizationScale
		set => this.wvc.RasterizationScale := Value
	}
	ShouldDetectMonitorScaleChanges { ;Boolean => Determines whether the WebView will detect monitor scale changes
		get => this.wvc.ShouldDetectMonitorScaleChanges
		set => this.wvc.ShouldDetectMonitorScaleChanges := Value
	}
	BoundsMode { ;Boolean => Gets or sets the WebView bounds mode
		get => this.wvc.BoundsMode
		set => this.wvc.BoundsMode := Value
	}
	AllowExternalDrop { ;Boolean => Gets or sets the WebView allow external drop property
		get => this.wvc.AllowExternalDrop
		set => this.wvc.AllowExternalDrop := Value
	}
	;NotifyParentWindowPositionChanged() => this.wvc.NotifyParentWindowPositionChanged() ;Seemingly Unused
	SetBoundsAndZoomFactor(bounds, zoomFactor) => this.wvc.SetBoundsAndZoomFactor(bounds, zoomFactor) ;Updates Bounds and ZoomFactor properties at the same time
	MoveFocus(reason) => this.wvc.MoveFocus(reason) ;Moves focus into WebView

	;-------------------------------------------------------------------------------------------
	;WebView2Core class assignments
	AddAHKObjHelper() => this.wv.AddAHKObjHelper()
	Settings => this.wv.Settings ;Returns Map() of Settings
		AreBrowserAcceleratorKeysEnabled { ;Boolean => Determines whether browser-specific accelerator keys are enabled
			get => this.Settings.AreBrowserAcceleratorKeysEnabled
			set =>  this.Settings.AreBrowserAcceleratorKeysEnabled := Value
		}
		AreDefaultContextMenusEnabled { ;Boolean => Determines whether the default context menus are shown to the user in WebView
			get => this.Settings.AreDefaultContextMenusEnabled
			set => this.Settings.AreDefaultContextMenusEnabled := Value
		}
		AreDefaultScriptDialogsEnabled { ;Boolean => Determines whether WebView renders the default JavaScript dialog box
			get => this.Settings.AreDefaultScriptDialogsEnabled
			set => this.Settings.AreDefaultScriptDialogsEnabled := Value
		}
		AreDevToolsEnabled { ;Boolean => Determines whether the user is able to use the context menu or keyboard shortcuts to open the DevTools window
			get => this.Settings.AreDevToolsEnabled
			set => this.Settings.AreDevToolsEnabled := Value
		}
		AreHostObjectsAllowed { ;Boolean => Determines whether host objects are accessible from the page in WebView
			get => this.Settings.AreHostObjectsAllowed
			set => this.Settings.AreHostObjectsAllowed := Value
		}
		HiddenPdfToolbarItems { ;Integer => Used to customize the PDF toolbar items
			/** 
			 * Bookmarks: 256
			 * FitPage: 64
			 * FullScreen: 2048
			 * MoreSettings: 4096
			 * None: 0
			 * PageLayout: 128
			 * PageSelector: 512
			 * Print: 2
			 * Rotate: 32
			 * Save: 1
			 * SaveAs: 4
			 * Search: 1024
			 * ZoomIn: 8
			 * ZoomOut: 16
			 * Add up numbers if you want to hide multiple items, Ex: 257 to hide Bookmarks and Save
			**/
			get => this.Settings.HiddenPdfToolbarItems
			set => this.Settings.HiddenPdfToolbarItems := Value
		}
		IsBuiltInErrorPageEnabled { ;Boolean => Determines whether to disable built in error page for navigation failure and render process failure
			get => this.Settings.IsBuiltInErrorPageEnabled
			set => this.Settings.IsBuiltInErrorPageEnabled := Value
		}
		IsGeneralAutofillEnabled { ;Boolean => Determines whether general form information will be saved and autofilled
			get => this.Settings.IsGeneralAutofillEnabled
			set => this.Settings.IsGeneralAutofillEnabled := Value
		}
		IsPasswordAutosaveEnabled { ;Boolean => Determines whether password information will be autosaved
			get => this.Settings.IsPasswordAutosaveEnabled
			set => this.Settings.IsPasswordAutosaveEnabled := Value
		}
		IsPinchZoomEnabled { ;Boolean => Determines the ability of the end users to use pinching motions on touch input enabled devices to scale the web content in the WebView2
			get => this.Settings.IsPinchZoomEnabled
			set => this.Settings.IsPinchZoomEnabled := Value
		}
		IsReputationCheckingRequired { ;Boolean => Determines whether SmartScreen is enabled when visiting web pages
			get => this.Settings.IsReputationCheckingRequired
			set => this.Settings.IsReputationCheckingRequired := Value
		}
		IsScriptEnabled { ;Boolean => Determines whether running JavaScript is enabled in all future navigations in the WebView
			get => this.Settings.IsScriptEnabled
			set => this.Settings.IsScriptEnabled := Value
		}
		IsStatusBarEnabled { ;Boolean => Determines whether the status bar is displayed
			get => this.Settings.IsStatusBarEnabled
			set => this.Settings.IsStatusBarEnabled := Value
		}
		IsSwipeNavigationEnabled { ;Boolean => Determines whether the end user to use swiping gesture on touch input enabled devices to navigate in WebView2
			get => this.Settings.IsSwipeNavigationEnabled
			set => this.Settings.IsSwipeNavigationEnabled := Value
		}
		IsWebMessageEnabled { ;Boolean => Determines whether communication from the host to the top-level HTML document of the WebView is allowed
			get => this.Settings.IsWebMessageEnabled
			set => this.Settings.IsWebMessageEnabled := Value
		}
		IsZoomControlEnabled { ;Boolean => Determines whether the user is able to impact the zoom of the WebView
			get => this.Settings.IsZoomControlEnabled
			set => this.Settings.IsZoomControlEnabled := Value
		}
		UserAgent { ;String => Determines WebView2's User Agent
			get => this.Settings.UserAgent
			set => this.Settings.UserAgent := Value
		}

	Source => this.wv.Source ;Returns Uri of current page
	Navigate(uri) => this.wv.Navigate(uri) ;Navigate to new Uri
	NavigateToString(htmlContent) => this.wv.NavigateToString(htmlContent) ;Navigate to text (essentially create a webpage from a string)
	ExecuteScript(script, callback := 0) => this.wv.ExecuteScript(script, callback) ;Execute code on the current Webpage
	CapturePreview(imageFormat, imageStream, handler) => this.wv.CapturePreview(imageFormat, imageStream, handler) ;Take a "screenshot" of the current WebView2 content
	Reload() => this.wv.Reload() ;Reloads the current page
	PostWebMessageAsJson(webMessageAsJson) => this.wv.PostWebMessageAsJson(webMessageAsJson) ;Posts the specified JSON message to the top level document in this WebView
	PostWebMessageAsString(webMessageAsString) => this.wv.PostWebMessageAsString(webMessageAsString) ;Posts the specified STRING message to the top level document in this WebView
		/**
		 * In order to use PostWebMessageAsJson() or PostWebMessageAsString(), you'll need to setup your webpage to listen to messages
		 * First, MyWindow.Settings.IsWebMessageEnabled must be set to true
		 * On your webpage itself, you'll need to setup an EventListner and Handler for the WebMessages
		 * 		window.chrome.webview.addEventListener('message', ahkWebMessage);
		 * 		function ahkWebMessage(Msg) {
		 * 			console.log(Msg);
		 * 		}
		**/

	CallDevToolsProtocolMethod(methodName, parametersAsJson, handler) => this.wvc.CallDevToolsProtocolMethod(methodName, parametersAsJson, handler) ;Runs an DevToolsProtocol method
	BrowserProcessId => this.wv.BrowserProcessId ;Returns the process ID of the browser process that hosts the WebView2
	CanGoBack => this.wv.CanGoBack ;Returns true if the WebView is able to navigate to a previous page in the navigation history
	CanGoForward => this.wv.CanGoForward ;Returns true if the WebView is able to navigate to a next page in the navigation history
	GoBack() => this.wv.GoBack() ;GoBack to the previous page in the navigation history
	GoForward() => this.wv.GoForward() ;GoForward to the next page in the navigation history
	GetDevToolsProtocolEventReceiver(eventName) => this.wv.GetDevToolsProtocolEventReceiver(eventName) ;Gets a DevTools Protocol event receiver that allows you to subscribe to a DevToolsProtocol event
	Stop() => this.wv.Stop() ;Stops all navigations and pending resource fetches
	DocumentTitle => this.wv.DocumentTitle ;Returns the DocumentTitle of the current webpage
	AddHostObjectToScript(objName, Obj) => this.wv.AddHostObjectToScript(objName, Obj) ;Create object link between the WebView2 and the AHK Script
	RemoveHostObjectFromScript(objName) => this.wv.RemoveHostObjectFromScript(objName) ;Delete object link from the WebView2
	OpenDevToolsWindow() => this.wv.OpenDevToolsWindow() ;Opens DevTools for the current WebView2
	ContainsFullScreenElement => this.wv.ContainsFullScreenElement ;Returns true if the WebView contains a fullscreen HTML element
	AddWebResourceRequestedFilter(uri, resourceContext) => this.wv.AddWebResourceRequestedFilter(uri, resourceContext) ;Adds a URI and resource context filter for the WebResourceRequested event
	RemoveWebResourceRequestedFilter(uri, resourceContext) => this.wv.RemoveWebResourceRequestedFilter(uri, resourceContext) ;Removes a matching WebResource filter that was previously added for the WebResourceRequested event
	NavigateWithWebResourceRequest(request) => this.wv.NavigateWithWebResourceRequest(request) ;Navigates using a constructed CoreWebView2WebResourceRequest object
	CookieManager => this.wv.CookieManager ;Gets the CoreWebView2CookieManager object associated with this CoreWebView2
		GetCookies(uri, handler) => this.CookieManager.GetCookies(uri, handler) ;Gets a list of cookies matching the specific URI
		/**
		 * You have to create a handler to be able to pass to the Method
		 * GetCookiesHandlerFunc := WebView2.Handler(GetCookiesHandler)
		 * 
		 * Then you have to define the handler itself
		 * GetCookiesHandler(Msg) {}
		 * 
		 * Finally you can call the Method
		 * MyWindow.GetCookies("https://google.com", GetCookiesHandlerFunc)
		**/

	Environment => this.wv.Environment ;Returns Map() of Environment settings
		BrowserVersionString => this.Environment.BrowserVersionString ;Returns the browser version info of the current CoreWebView2Environment, including channel name if it is not the stable channel
		FailureReportFolderPath => this.Environment.FailureReportFolderPath ;Returns the failure report folder that all CoreWebView2s created from this environment are using
		UserDataFolder => this.Environment.UserDataFolder ;Returns the user data folder that all CoreWebView2s created from this environment are using
		CreateWebResourceRequest(uri, method, postData, headers) => this.Environment.CreateWebResourceRequest(uri, method, postData, headers) ;Creates a new CoreWebView2WebResourceRequest object
		CreateCoreWebView2CompositionController(parentWindow, handler) => this.Environment.CreateCoreWebView2CompositionController(parentWindow, handler) ;Creates a new WebView for use with visual hosting
		CreateCoreWebView2PointerInfo() => this.Environment.CreateCoreWebView2PointerInfo() ;Returns Map() of a combined win32 POINTER_INFO, POINTER_TOUCH_INFO, and POINTER_PEN_INFO object
		GetAutomationProviderForWindow(hwnd) => this.Environment.GetAutomationProviderForWindow(hwnd) ;PRODUCES ERROR, REACH OUT TO THQBY
		CreatePrintSettings() => this.Environment.CreatePrintSettings() ;Creates the CoreWebView2PrintSettings used by the PrintToPdfAsync(String, CoreWebView2PrintSettings) method
		GetProcessInfos() => this.Environment.GetProcessInfos() ;Returns the list of all CoreWebView2ProcessInfo using same user data folder except for crashpad process
		CreateContextMenuItem(label, iconStream, kind) => this.Environment.CreateContextMenuItem(label, iconStream, kind) ;PRODUCES ERROR, REACH OUT TO THQBY
		CreateCoreWebView2ControllerOptions() => this.Environment.CreateCoreWebView2ControllerOptions() ;PRODUCES ERROR, REACH OUT TO THQBY
		CreateCoreWebView2ControllerWithOptions(parentWindow, options, handler) => this.Environment.CreateCoreWebView2ControllerWithOptions(parentWindow, options, handler) ;PRODUCES ERROR, REACH OUT TO THQBY -- I think the issue is part of the `CreateCoreWEbView2ControllerOptions()` method
		CreateCoreWebView2CompositionControllerWithOptions(parentWindow, options, handler) => this.Environment.CreateCoreWebView2CompositionControllerWithOptions(parentWindow, options, handler) ;;PRODUCES ERROR, REACH OUT TO THQBY -- I think the issue is part of the `CreateCoreWEbView2ControllerOptions()` method
		CreateSharedBuffer(size) => this.Environment.CreateSharedBuffer(size) ;Create a shared memory based buffer with the specified size in bytes -- PRODUCES ERROR, REACH OUT TO THQBY

	Resume() => this.wv.Resume() ;Resumes the WebView so that it resumes activities on the web page
	IsSuspended => this.wv.IsSuspended ;Returns true if the WebView is suspended
	SetVirtualHostNameToFolderMapping(hostName, folderPath, accessKind) => this.wv.SetVirtualHostNameToFolderMapping(hostName, folderPath, accessKind) ;Sets a mapping between a virtual host name and a folder path to make available to web sites via that host name
	ClearVirtualHostNameToFolderMapping(hostName) => this.wv.ClearVirtualHostNameToFolderMapping(hostName) ;Clears a host name mapping for local folder that was added by SetVirtualHostNameToFolderMapping()
	OpenTaskManagerWindow() => this.wv.OpenTaskManagerWindow() ;Opens the Browser Task Manager view as a new window in the foreground
	IsMuted { ;Indicates whether all audio output from this CoreWebView2 is muted or not. Set to true will mute this CoreWebView2, and set to false will unmute this CoreWebView2. true if audio is muted
		get => this.wv.IsMuted
		set => this.wv.IsMuted := Value
	}
	IsDocumentPlayingAudio => this.wv.IsDocumentPlayingAudio ;Returns true if audio is playing even if IsMuted is true
	IsDefaultDownloadDialogOpen => this.wv.IsDefaultDownloadDialogOpen ;Returns true if the default download dialog is currently open
	OpenDefaultDownloadDialog() => this.wv.OpenDefaultDownloadDialog() ;Opens the DownloadDialog Popup Window
	CloseDefaultDownloadDialog() => this.wv.CloseDefaultDownloadDialog() ;Closes the DownloadDialog Popup Window
	DefaultDownloadDialogCornerAlignment { ;Position of DownloadDialog does not update until after the WebView2 position or size has changed
		get => this.wv.DefaultDownloadDialogCornerAlignment ;Return the current corner the DownloadDialog will show up in (0 := TopLeft, 1 := TopRight, 2 := BottomLeft, 3 := BottomRight)
		set => this.wv.DefaultDownloadDialogCornerAlignment := Value ;Set the corner of the WebView2 that the DownloadDialog will show up in (0 := TopLeft, 1 := TopRight, 2 := BottomLeft, 3 := BottomRight)
	}
	DefaultDownloadDialogMargin { ;Working, but I don't know how to accurately assign a new Margin yet. We can assign one via an Integer, but it's hit and miss to get the position correct
		get => this.wv.DefaultDownloadDialogMargin
		set => this.wv.DefaultDownloadDialogMargin := Value
	}
	CallDevToolsProtocolMethodForSession(sessionId, methodName, parametersAsJson, handler) => this.wv.CallDevToolsProtocolMethodForSession(sessionId, methodName, parametersAsJson, handler) ;Runs a DevToolsProtocol method for a specific session of an attached target
	StatusBarText => this.wv.StatusBarText ;Returns the current text of the WebView2 StatusBar
	Profile => this.wv.Profile ;Returns the associated CoreWebView2Profile object of CoreWebView2
	FaviconUri => this.wv.FaviconUri ;Returns the Uri as a string of the current Favicon. This will be an empty string if the page does not have a Favicon
	GetFavicon(format, completedHandler) => this.wv.GetFavicon(format, completedHandler) ;Get the downloaded Favicon image for the current page and copy it to the image stream
	
	Print(printSettings, handler) => this.wv.Print(printSettings, handler) ;Print the current web page asynchronously to the specified printer with the provided settings
		/**
		 * You have to create a handler to be able to pass to the Method
		 * PrintHandlerFunc := WebView2.Handler(PrintHandler)
		 * PrintHandler(Msg) {}
		 * printSettings := MyWindow.CreatePrintSettings()
		 * printSettings.PrinterName := "HP Color LaserJet MFP M477fdn" ;this needs to match what you see in your 'Printers and Scanners' window
		 * MyWindow.Print(printSettings, PrintHandlerFunc)
		**/
	PrintToPdf(resultFilePath, printSettings, handler) => this.wv.PrintToPdf(resultFilePath, printSettings, handler) ;Print the current page to PDF with the provided settings
	ShowPrintUI(printDialogKind) => this.wv.ShowPrintUI(printDialogKind) ;Opens the print dialog to print the current web page. Browser printDialogKind := 0, System printDialogKind := 1
	PrintToPdfStream(printSettings, handler) => this.wv.PrintToPdfStream(printSettings, handler) ;Provides the PDF data of current web page for the provided settings to a Stream
	PostSharedBufferToScript(sharedBuffer, access, additionalDataAsJson) => this.wv.PostSharedBufferToScript(sharedBuffer, access, additionalDataAsJson) ;Share a shared buffer object with script of the main frame in the WebView
	MemoryUsageTargetLevel { ;0 = Normal, 1 = Low; Low can be used for apps that are inactive to conserve memory usage
		get => this.wv.MemoryUsageTargetLevel
		set => this.wv.MemoryUsageTargetLevel := Value
	}

	;-------------------------------------------------------------------------------------------
	;Handler Assignments
	static PlaceholderHandler(handler, ICoreWebView2, args) {
		MsgBox(handler, "PlaceholderHandler")
	}

	;Controller
	ZoomFactorChanged(handler) => this.ZoomFactorChangedHandler := this.wv.ZoomFactorChanged(handler)
	MoveFocusRequested(handler) => this.MoveFocusRequestedHandler := this.wv.MoveFocusRequested(handler)
	GotFocus(handler) => this.GotFocusHandler := this.wvc.GotFocus(handler)
	LostFocus(handler) => this.LostFocusHandler := this.wv.LostFocus(handler)
	AcceleratorKeyPressed(handler) => this.AcceleratorKeyPressedHandler := this.wv.AcceleratorKeyPressed(handler)
	RasterizationScaleChanged(handler) => this.RasterizationScaleChangedHandler := this.wv.RasterizationScaleChanged(handler)

	;Core
	NavigationStarting(handler) => this.NavigationStartingHandler := this.wv.NavigationStarting(handler)
	ContentLoading(handler) => this.ContentLoadingHandler := this.wv.ContentLoading(handler)
	SourceChanged(handler) => this.SourceChangedHandler := this.wv.SourceChanged(handler)
	HistoryChanged(handler) => this.HistoryChangedHandler := this.wv.HistoryChanged(handler)
	NavigationCompleted(handler) => this.NavigationCompletedHandler := this.wv.NavigationCompleted(handler)
	ScriptDialogOpening(handler) => this.ScriptDialogOpeningHandler := this.wv.ScriptDialogOpening(handler)
	PermissionRequested(handler) => this.PermissionRequestedHandler := this.wv.PermissionRequested(handler)
	ProcessFailed(handler) => this.ProcessFailedHandler := this.wv.ProcessFailed(handler)
	WebMessageReceived(handler) => this.WebMessageReceivedHandler := this.wv.WebMessageReceived(handler)
	NewWindowRequested(handler) => this.NewWindowRequestedHandler := this.wv.NewWindowRequested(handler)
	DocumentTitleChanged(handler) => this.DocumentTitleChangedRequested := this.wv.DocumentTitleChanged(handler)
	ContainsFullScreenElementChanged(handler) => this.ContainsFullScreenElementChangedHandler := this.wv.ContainsFullScreenElementChanged(handler)
	WebResourceRequested(handler) => this.WebResourceRequestedHandler := this.wv.WebResourceRequested(handler)
	WindowCloseRequested(handler) => this.WindowCloseRequestedHandler := this.wv.WindowCloseRequested(handler)
	WebResourceResponseReceived(handler) => this.WebResourceResponseReceivedHandler := this.wv.WebResourceResponseReceived(handler)
	DOMContentLoaded(handler) => this.DOMContentLoadedHandler := this.wv.DOMContentLoaded(handler)
	TrySuspend(handler) => this.TrySuspendHandler := WebView2.Handler(handler)
	FrameCreated(handler) => this.FrameCreatedHandler := this.wv.FrameCreated(handler)
	DownloadStarting(handler) => this.DownloadStartingHandler := this.wv.DownloadStarting(handler)
	ClientCertificateRequested(handler) => this.ClientCertificateRequestedHandler := this.wv.ClientCertificateRequested(handler)
	IsMutedChanged(handler) => this.IsMutedChangedHandler := this.wv.IsMutedChanged(handler)
	IsDocumentPlayingAudioChanged(handler) => this.IsDocumentPlayingAudioChangedHandler := this.wv.IsDocumentPlayingAudioChanged(handler)
	IsDefaultDownloadDialogOpenChanged(handler) => this.IsDefaultDownloadDialogOpenChangedHandler := this.wv.IsDefaultDownloadDialogOpenChanged(handler)
	BasicAuthenticationRequested(handler) => this.BasicAuthenticationRequestedHandler := this.wv.BasicAuthenticationRequested(handler)
	ContextMenuRequested(handler) => this.ContextMenuRequestedHandler := this.wv.ContextMenuRequested(handler)
	StatusBarTextChanged(handler) => this.StatusBarTextChangedHandler := this.wv.StatusBarTextChanged(handler)
	ServerCertificateErrorDetected(handler) => this.ServerCertificateErrorDetectedHandler := this.wv.ServerCertificateErrorDetected(handler)
	ClearServerCertificateErrorActions(handler) => this.ClearServerCertificateErrorActionsHandler := WebView2.Handler(handler)
	FaviconChanged(handler) => this.FaviconChangedHandler := this.wv.FaviconChanged(handler)
	LaunchingExternalUriScheme(handler) => this.LaunchingExternalUriSchemeHandler := this.wv.LaunchingExternalUriScheme(handler)

	;ExecuteScriptCompleted
	ExecuteScriptCompleted(handler) => this.ExecuteScriptCompletedHandler := WebView2.Handler(handler)

	/**
	 * The following event handlers are commented out for the time being.
	 * Their assignments are not accurate and cannot be used directly,
	 * I'm leaving them here for easy tracking of event handlers and
	 * I may revisit fixing them in the future.  
	**/
	/*
	;DownloadOperation
	BytesReceivedChanged(handler) => this.BytesReceivedChangedHandler := this.do.BytesReceivedChanged(handler)
	EstimatedEndTimeChanged(handler) => this.EstimatedEndTimeChangedHandler := WebView2.Handler(handler)
	StateChanged(handler) => this.StateChangedHandler := WebView2.Handler(handler)

	;Environment
	NewBrowserVersionAvailable(handler) => this.NewBrowserVersionAvailableHandler := this.wv.NewBrowserVersionAvailable(handler)
	BrowserProcessExited(handler) => this.BrowserProcessExitedHandler := this.wv.BrowserProcessExited(handler)
	ProcessInfosChanged(handler) => this.ProcessInfosChangedHandler := this.wv.ProcessInfosChanged(handler)

	;Frame
	FrameNameChanged(handler) => this.FrameNameChangedHandler := this.wv.NameChanged(handler)
	FrameDestroyed(handler) => this.FrameDestroyedHandler := this.wv.FrameDestroyed(handler)
	FrameNavigationStarting(handler) => this.FrameNavigationStartingHandler := this.wv.FrameNavigationStarting(handler)
	FrameNavigationCompleted(handler) => this.FrameNavigationCompletedHandler := this.wv.FrameNavigationCompleted(handler)
	FrameContentLoading(handler) => this.FrameContentLoadingHandler := this.wv.FrameContentLoading(handler)
	FrameDOMContentLoaded(handler) => this.FrameDOMContentLoadedHandler := this.wv.FrameDOMContentLoaded(handler)
	FrameWebMessageReceived(handler) => this.FrameWebMessageReceivedHandler := this.wv.FrameWebMessageReceived(handler)
	FramePermissionRequested(handler) => this.FramePermissionRequestedHandler := this.wv.FramePermissionRequested(handler)

	;Profile
	ClearBrowsingDataAll(handler) => this.ClearBrowsingDataAllHandler := this.wv.ClearBrowsingDataAll(handler)

	;CompositionController
	CursorChanged(handler) => this.CursorChangedHandler := this.wv.CursorChanged(handler)

	;ContextMenuItem
	CustomItemSelected(handler) => this.CustomItemSelectedHandler := this.wv.CustomItemSelected(handler)

	;DevToolsProtocolEventReceiver
	DevToolsProtocolEventReceived(handler) => this.DevToolsProtocolEventReceivedHandler := this.wv.DevToolsProtocolEventReceived(handler)

	;WebResourceResponseView
	GetContent(handler) => this.GetContentHandler := this.wv.GetContent(handler)
	*/
}