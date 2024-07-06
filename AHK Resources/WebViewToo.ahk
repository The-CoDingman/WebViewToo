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
;///////////////////////////////////////////////////////////////////////////////////////////

#Requires AutoHotkey v2.1-alpha.1 ;Sorry! You'll have to use the Alpha with this latest version: https://www.autohotkey.com/download/2.1/AutoHotkey_2.1-alpha.1.1.zip
#Include WebView2.ahk

class WebViewToo {
    static Template := {}
    static Template.Framework := "
    (
        <!DOCTYPE html>
		<html>
			<head>
				<meta http-equiv="X-UA-Compatible" content="IE=edge">				
				<style>{2}</style>
			</head>

			<body>
				<div class="main">{1}</div>
				<script>{3}</script>
			</body>
		</html>
    )"
    static Template.JS := ""
    static Template.Name := "Template.html"
    static Template.HTML := "<iframe style='height:100%;width:100%;border:0;'' src='https://the-codingman.github.io/WebViewToo/WebViewToo.html'></iframe>"
	static Template.CSS := "html, body {width: 100%; height: 100%;margin: 0; padding: 0;font-family: sans-serif;} body {display: flex;flex-direction: column;} .main {flex-grow: 1;overflow: hidden;}"

    static UniqueID => WebViewToo.CreateUniqueID()
    static CreateUniqueID() {
        SplitPath(A_ScriptName,,,, &OutNameNoExt)
        Loop Parse, OutNameNoExt {
            ID .= Mod(A_Index, 3) ? Format("{:X}", Ord(A_LoopField)) : "-" Format("{:X}", Ord(A_LoopField))
        }
        return RTrim(StrLower(ID), "-")
    }

    static TempDir := A_Temp "\" WebViewToo.UniqueID
    static DllName := "WebView2Loader_" (A_PtrSize * 8) ".dll"

    __New(Html := WebViewToo.Template.HTML, CSS := WebViewToo.Template.CSS, JS := WebViewToo.Template.JS, CustomCaption := False) {
        this.Gui := Gui("+Resize")
        this.Gui.BackColor := "000000"
        this.CustomCaption := CustomCaption
        this.Gui.MarginX := this.Gui.MarginY := 0
        this.Gui.BorderSize := 0, this.MaximizedBorderSize := 7
        this.Gui.Add("Button", "x0 y0 vNCLBUTTONDOWN_Sink Hidden", "John Cena")
        this.Gui.Add("Text", "x" this.BorderSize " y" this.BorderSize " vWebViewTooContainer BackgroundTrans", "If you can see this, something went wrong.")
        this.wvc := !A_IsCompiled ? WebView2.create(this.Gui["WebViewTooContainer"].Hwnd) : WebView2.create(this.Gui["WebViewTooContainer"].Hwnd,,,,,, WebViewToo.DllName)
        this.IsVisible := 1, this.wv := this.wvc.CoreWebView2
        this.Gui.OnEvent("Size", (*) => this.Fill())
        this.AddCallbackToScript("Close", this.Close)
        this.AddCallbackToScript("DragWindow", this.DragWindow)
        this.AddCallbackToScript("Minimize", this.Minimize)
        this.AddCallbackToScript("Maximize", this.Maximize)
        this.AddScriptToExecuteOnDocumentCreated("const ahk = window.chrome.webview.hostObjects", 0)
        this.wv.NavigateToString(Format(WebViewToo.Template.Framework, Html, CSS, JS))
        if (this.CustomCaption) {
            this.CustomCaptionBarInit()
        }
    }

    __Delete() {
        MsgBox("Deleting Object", "WebViewToo.__Delete()", "262144")
    }

    ;-------------------------------------------------------------------------------------------
    ;Static WebViewToo Methods
	static ConvertColor(RGB) => (RGB := RGB ~= "^0x" ? RGB : "0x" RGB, (((RGB & 0xFF) << 16) | (RGB & 0xFF00) | (RGB >> 16 & 0xFF)) << 8 | 0xFF) ;Must be a string

    static CreateFileFromResource(ResourceName) { ;Create a file from an installed resource -- works like a dynamic `FileInstall()`
        Module := DllCall("GetModuleHandle", "Ptr", 0, "Ptr")
        Resource := DllCall("FindResource", "Ptr", Module, "Str", ResourceName, "UInt", RT_RCDATA := 10, "Ptr")
        ResourceSize := DllCall("SizeofResource", "Ptr", Module, "Ptr", Resource)
        ResourceData := DllCall("LoadResource", "Ptr", Module, "Ptr", Resource, "Ptr")
        ConvertedData := DllCall("LockResource", "Ptr", ResourceData, "Ptr")
        TextData := StrGet(ConvertedData, ResourceSize, "UTF-8")
        SplitPath(ResourceName, &OutFileName, &OutDir, &OutExt)

        if (!DirExist(WebViewToo.TempDir "\" OutDir)) {
            DirCreate(WebViewToo.TempDir "\" OutDir)
        }

        if (FileExist(WebViewToo.TempDir "\" ResourceName)) {
            ExistingFile := FileOpen(WebViewToo.TempDir "\" ResourceName, "r")
            ExistingFile.RawRead(TempBuffer := Buffer(ResourceSize))
            ExistingFile.Close()
            if (DllCall("ntdll\memcmp", "Ptr", TempBuffer, "Ptr", ConvertedData, "Ptr", ResourceSize)) {
                FileSetAttrib("-R", WebViewToo.TempDir "\" ResourceName)
                FileDelete(WebViewToo.TempDir "\" ResourceName)
            }
        }

        if (!FileExist(WebViewToo.TempDir "\" ResourceName)) {
            TempFile := FileOpen(WebViewToo.TempDir "\" ResourceName, "w")
            TempFile.RawWrite(ConvertedData, ResourceSize)
            TempFile.Close()
            FileSetAttrib("+HR", WebViewToo.TempDir "\" OutDir)
            FileSetAttrib("+HR", WebViewToo.TempDir "\" ResourceName)
        }

        StartingPos := 1
        while (RegExMatch(TextData, "<script.*?src=[`"'](?!https)(.*?)[`"']>", &Match, StartingPos) || RegExMatch(TextData, "<link.*?href=[`"'](?!https)(.*?)[`"'] rel=`"stylesheet`">", &Match, StartingPos)) {
            WebViewToo.CreateFileFromResource(OutDir "\" StrReplace(Match[1], "/", "\"))
            StartingPos := StrLen(Match[]) + Match.Pos
        }
    }

    static EscapeHTML(Text) => StrReplace(StrReplace(StrReplace(StrReplace(StrReplace(Text, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"), "`"", "&quot;"), "'", "&#039;")

    static EscapeJS(Text) => StrReplace(StrReplace(StrReplace(Text, '\', '\\'), '"', '\"'), '`n', '\n')

    static forEach(Obj, Parent := "Default") {
		output := ""
		try {
			for k, v, in Obj {
				try {
					output .= Parent " >> " k ": " v "`n"
				} catch {
					output .= WebViewToo.forEach(v, Parent " >> " k)
				}
			}
		}
		return output
	}

    static FormatHTML(FormatStr, Values*) {
        for Index, Value, in Values {
            Values[Index] := WebViewToo.EscapeHTML(Value)
        }
        return Format(FormatStr, Values*)
    }

    ;-------------------------------------------------------------------------------------------
    ;WebViewToo class assignments    
    AddCallbackToScript(CallbackName, Callback) => this.AddHostObjectToScript(CallbackName, Callback.Bind(this))
    BorderSize {
        /**
         * A minimum BorderSize of 1 is required when using the CustomCaption
         * This is what allows us to resize the window by grabbing the GUI border
        **/
		get => this.Gui.BorderSize
		set {
			this.Gui.BorderSize := Value
			this.Gui["WebViewTooContainer"].Move(this.BorderSize, this.BorderSize)
			this.Fill()
		}
	}

    CustomCaptionBarInit() {
		this.Gui.Opt("-Caption")
		this.BorderSize := 1
		this.Gui.OnMessage(WM_NCHITTEST := 0x0084, (GuiObj, wParam, lParam, Msg) {
			Critical(-1)
			GuiObj.GetPos(&gX, &gY, &gWidth, &gHeight)
			X := lParam << 48 >> 48, Y := lParam << 32 >> 48, HL := X < gX + (this.Gui.BorderSize * 2), HR := X >= gX + gWidth - (this.Gui.BorderSize * 2), HT := Y < gY + (this.Gui.BorderSize * 2), HB := Y >= gy + gHeight - (this.Gui.BorderSize * 2)
			ReturnCode := HT && HL ? 0xD : HT && HR ? 0xE : HT ? 0xC : HB && HL ? 0x10 : HB && HR ? 0x11 : HB ? 0xF : HL ? 0xA : HR ? 0xB : 0
			if (ReturnCode)
				return ReturnCode
		})
		this.Gui.OnMessage(WM_NCACTIVATE := 0x0086, (GuiObj, wParam, lParam, Msg) {
			return 1
		})
		this.Gui.OnMessage(WM_NCCALCSIZE := 0x0083, (GuiObj, wParam, lParam, Msg) {
			return 0
		})
		DllCall("Dwmapi.dll\DwmSetWindowAttribute", "Ptr", this.Gui.Hwnd, "UInt", DWMWA_WINDOW_CORNER_PREFERENCE := 33, "Ptr*", pvAttribute := 2, "UInt", 4) ;May not work or even cause errors on Win10
	}

    Close() {
        WinClose("ahk_id" this.Hwnd)
    }

    Debug() {
        this.OpenDevToolsWindow()
    }

    DragWindow() {
        ControlClick(this.Gui["NCLBUTTONDOWN_Sink"], this.Gui,, "Left", 1)
        PostMessage(0x00A1, 2,, this.Hwnd)
    }

	GetFormData(FormElement, UseIdAsName := true) {
		FormData := StrSplit(this.QueryPage("var Elements = Array.from(document.getElementById('" FormElement "').querySelectorAll('input'));var IdArray = ''; var ValueArray = ''; Elements.forEach((input) => {IdArray += input.id + '[WEB_VIEW_TOO_BREAK]';ValueArray += (input.type == 'checkbox' ? input.checked : input.value) + '[WEB_VIEW_TOO_BREAK]'});var Output = IdArray.replace(/\[WEB_VIEW_TOO_BREAK\]$/gm, '') + '[WEB_VIEW_TOO_ID_ARRAY_END]' + ValueArray.replace(/\[WEB_VIEW_TOO_BREAK\]$/gm, '');Output;"), "[WEB_VIEW_TOO_ID_ARRAY_END]")
		IdArray := StrSplit(FormData[1], "[WEB_VIEW_TOO_BREAK]"), ValueArray := StrSplit(FormData[2], "[WEB_VIEW_TOO_BREAK]")
		FormDataArray := []
		Loop(IdArray.length) {
			FormDataArray.Push(Map("Id", IdArray[A_Index], "Value", ValueArray[A_Index]))
		}
		return FormDataArray
	}

    Load(Filename) {
        if (RegExMatch(Filename, "^https?:\/\/")) {
            Url := Filename
        } else {
            if (A_IsCompiled) {
                if (!DirExist(WebViewToo.TempDir)) {
                    DirCreate(WebViewToo.TempDir)
                }
                WebViewToo.CreateFileFromResource(Filename)
                Url := WebViewToo.TempDir "\" Filename
            } else {
                Url := A_WorkingDir "\" Filename
            }
        }
        this.Navigate(Url)
    }

    MaximizedBorderSize {
        get => this.Gui.MaximizedBorderSize
        set => this.Gui.MaximizedBorderSize := Value
    }

	qp(Script, Timeout := 5000) => this.QueryPage(Script, Timeout)

	QueryPage(Script, Timeout := 5000) {
		static QueryCount := 0
		QueryName := "QueryPage" (++QueryCount), QueryStart := A_TickCount, QueryResult := unset
		this.AddHostObjectToScript(QueryName, (Response) => (
			QueryResult := Response,
			this.RemoveHostObjectFromScript(QueryName)
		))
		this.ExecuteScript("ahk." QueryName "(eval(`"" WebViewToo.EscapeJS(Script) "`"));")
		while(!IsSet(QueryResult) && (A_TickCount - QueryStart < Timeout)) {
			Sleep(10)
		}
		return QueryResult ?? ""
	}

    SimplePrintToPdf(Orientation := "portrait") {
		Loop {
			FileName := FileSelect("S", tFileName := IsSet(FileName) ? FileName : "",, "*.pdf")
			if (FileName = "") {
				return (MsgBox("Print Canceled", "Print to PDF", "262144"))
			}

			SplitPath(FileName, &OutFileName, &OutDir, &OutExt)
			FileName := OutExt = "" ? FileName ".pdf" : Filename
			if (FileExist(FileName)) {
				if (MsgBox(OutFileName " already exists.`nWould you like to overwrite it?", "Confirm Save As", "262196") = "No") {
					continue
				}
			}
			break
		}

		Settings := this.Environment.CreatePrintSettings()
		if (StrLower(Orientation) = "landscape") {
			Settings.Orientation := WebView2.PRINT_ORIENTATION.LANDSCAPE
		}
		else {
			Settings.Orientation := WebView2.PRINT_ORIENTATION.PORTRAIT
		}
		simpleWebviewWindow := this, simpleFileName := FileName
		this.PrintToPdf(FileName, Settings, simplePrintToPdfHandler)

		SimplePrintToPdfHandler(HandlerPtr, pWebviewWindow, Success) {
			pWebviewWindow := simpleWebviewWindow
			if (!Success) {
				MsgBox("An error occurred while attempting to save the file.`n" OutFileName, "Simple Print To Pdf", "262144")
			} else {
				if (MsgBox("Would you like to open this PDF?", "Print to PDF", "262148") = "Yes") {
					Run(FileName)
				}
			}
		}
	}

	AddScriptToExecuteOnDocumentCreated(javaScript, Handler) => this.wv.AddScriptToExecuteOnDocumentCreated(javaScript, Handler) ;unsure where it goes

    ;-------------------------------------------------------------------------------------------
    ;Inherited GUI Methods
    Destroy() {
        this.wvc.Close() ;Close the WebView2Controller before destroying the Gui
        this.Gui.Destroy()
        ;return "" ;UpdateCheck -- Clearing the object isn't working
    }

    Flash(Blink := True) {
        this.Gui.Flash(Blink)
    }

    GetClientPos(Params*) => this.Gui.GetClientPos(Params*)

    GetPos(Params*) => this.Gui.GetPos(Params*)

    Hide() {
        this.Gui.Hide()
    }

    Maximize() {
        if (DllCall("IsZoomed", "UPtr", this.Hwnd)) {
            this.Gui.Restore()
            if (this.CustomCaption) {
                this.BorderSize := this.HasOwnProp("RestoredBorderSize") ? this.RestoredBorderSize : this.Gui.BorderSize
            }
        } else {
            this.Gui.Maximize()
            if (this.CustomCaption) {
                this.RestoredBorderSize := this.BorderSize
                this.BorderSize := this.MaximizedBorderSize
            }
        }
        this.ExecuteScript("document.body.classList.toggle('ahk-maximized')")
        this.Fill()
    }

    Minimize() {
        this.Gui.Minimize()
    }

    Move(Params*) => this.Gui.Move(Params*)

    OnEvent(EventName, Callback, AddRemove := unset) {
        this.Gui.OnEvent(EventName, (p*) => (p[1] := this, Callback(p*)), AddRemove?)
    }

    Opt(Options) {
        this.Gui.Opt(Options)
    }

    Restore() => this.Gui.Restore()

	Show(Options := "", Title := this.Title) {
		Width := RegExMatch(options, "w\s*\K\d+", &match) ? match[] : A_ScreenWidth / 2
		Height := RegExMatch(options, "h\s*\K\d+", &match) ? match[] : A_ScreenHeight / 2

		; AutoHotkey sizes the window incorrectly, trying to account for borders
		; that aren't actually there. Call the function AHK uses to offset and
		; apply the change in reverse to get the actual wanted size.
		if (this.CustomCaption) {  
			rect := Buffer(16, 0)
			DllCall("AdjustWindowRectEx",
				"Ptr", rect,		; LPRECT lpRect
				"UInt", WinGetStyle(this.Gui),	; DWORD  dwStyle
				"UInt", 0,			; BOOL   bMenu
				"UInt", 0,			; DWORD  dwExStyle
				"UInt"				; BOOL
			)
			Width += (NumGet(rect, 0, "Int") - NumGet(rect, 8, "Int")) ;+ (this.BorderSize * 2)
			Height += (NumGet(rect, 4, "Int") - NumGet(rect, 12, "Int")) ;+ (this.BorderSize * 2)
		}
		this.Gui.Title := Title
		this.Gui.Show(Options " w" Width " h" Height)
	}

    ;-------------------------------------------------------------------------------------------
    ;Inherited GUI Properites
    BackColor {
        get => this.Gui.BackColor
        set => this.Gui.BackColor := Value
    }
    FocusedCtrl => this.Gui.FocusedCtrl
    Hwnd => this.Gui.Hwnd
    MarginX {
        get => this.Gui.MarginX
        set => this.Gui.MarginX := Value
    }
    MarginY {
        get => this.Gui.MarginY
        set => this.Gui.MarginY := Value
    }
    MenuBar {
        get => this.Gui.MenuBar
        set {
            if (!this.CustomCaption) {
                this.Gui.MenuBar := Value
            }
        }
    }
    Name {
        get => this.Gui.Name
        set => this.Gui.Name := Value
    }
    Title {
        get => this.Gui.Title
        set {
            this.Gui.Title := Value
            if (this.CustomCaption) {
                this.ExecuteScript("document.querySelector('.ahk-titleBar > span').textContent = '" Value "'")
            }
        }
    }

    ;-------------------------------------------------------------------------------------------
    ;Controller class assignments
    Fill() { ;Fills the available GUI space with the CoreWebView2Controller
        this.Gui.GetClientPos(&X, &Y, &Width, &Height)
        this.Gui["WebViewTooContainer"].Move(,, Width - (this.Gui.BorderSize * 2), Height - (this.Gui.BorderSize * 2))
        this.wvc.Fill()
    }
    CoreWebView2 => this.wvc.CoreWebView2 ;Gets the CoreWebView2 associated with this CoreWebView2Controller
    IsVisible { ;Boolean => Determines whether to show or hide the WebView
		get => this.wvc.IsVisible
		set => this.wvc.IsVisible := Value
	}
    Bounds { ;Rectangle => Gets or sets the WebView bounds
        /**
         * Returns a Buffer()
         * You can extract the X, Y, Width, and Height using NumGet()
         * X is at offset 0, Y at offset 4, Width at offset 8, Height at offset 12.
        **/
		get => this.wvc.Bounds

        /**
         * Value must be a Buffer(16) that you've inserted values into
         * using NumPut(). See the above notes regarding the appropriate offsets.
        **/
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
		set => this.wvc.DefaultBackgroundColor := WebViewToo.ConvertColor(Value)
        ;set => this.wvc.DefaultBackgroundColor := Value
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
	SetBoundsAndZoomFactor(Bounds, ZoomFactor) => this.wvc.SetBoundsAndZoomFactor(Bounds, ZoomFactor) ;Updates Bounds and ZoomFactor properties at the same time

	/**
	 * MoveFocus()
	 * 1: Next; Specifies that the focus is moved due to Tab traversal forward
	 * 2: Previous; Specifices that the focus is moved due to Tab traversal backward
	 * 0: Programmatic; Specifies that the code is settings focus into WebView
	**/
	MoveFocus(Reason) => this.wvc.MoveFocus(Reason) ;Moves focus into WebView    

	/**
	 * NotifyParentWindowPositionChanged()
	 * Notifies the WebView that the parent (or any ancestor) HWND moved
	 * Example: Calling this method updates dialog windows such as the DownloadDialog
	**/
	NotifyParentWindowPositionChanged() => this.wvc.NotifyParentWindowPositionChanged()
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
    Navigate(Uri) => this.wv.Navigate(Uri) ;Navigate to new Uri
	NavigateToString(HtmlContent) => this.wv.NavigateToString(HtmlContent) ;Navigate to text (essentially create a webpage from a string)
    ExecuteScript(Script, Callback := 0) => this.wv.ExecuteScript(Script, Callback) ;Execute code on the current Webpage
	CapturePreview(ImageFormat, ImageStream, Handler) => this.wv.CapturePreview(ImageFormat, ImageStream, Handler) ;Take a "screenshot" of the current WebView2 content
    Reload() => this.wv.Reload() ;Reloads the current page

	/**
	 * In order to use PostWebMessageAsJson() or PostWebMessageAsString(), you'll need to setup your webpage to listen to messages
	 * First, MyWindow.Settings.IsWebMessageEnabled must be set to true
	 * On your webpage itself, you'll need to setup an EventListner and Handler for the WebMessages
	 * 		window.chrome.webview.addEventListener('message', ahkWebMessage);
	 * 		function ahkWebMessage(Msg) {
	 * 			console.log(Msg);
	 * 		}
	**/
	PostWebMessageAsJson(WebMessageAsJson) => this.wv.PostWebMessageAsJson(WebMessageAsJson) ;Posts the specified JSON message to the top level document in this WebView
	PostWebMessageAsString(WebMessageAsString) => this.wv.PostWebMessageAsString(WebMessageAsString) ;Posts the specified STRING message to the top level document in this WebView
    CallDevToolsProtocolMethod(MethodName, ParametersAsJson, Handler) => this.wvc.CallDevToolsProtocolMethod(MethodName, ParametersAsJson, Handler) ;Runs an DevToolsProtocol method
	BrowserProcessId => this.wv.BrowserProcessId ;Returns the process ID of the browser process that hosts the WebView2
	CanGoBack => this.wv.CanGoBack ;Returns true if the WebView is able to navigate to a previous page in the navigation history
	CanGoForward => this.wv.CanGoForward ;Returns true if the WebView is able to navigate to a next page in the navigation history
	GoBack() => this.wv.GoBack() ;GoBack to the previous page in the navigation history
	GoForward() => this.wv.GoForward() ;GoForward to the next page in the navigation history
	GetDevToolsProtocolEventReceiver(EventName) => this.wv.GetDevToolsProtocolEventReceiver(EventName) ;Gets a DevTools Protocol event receiver that allows you to subscribe to a DevToolsProtocol event
	Stop() => this.wv.Stop() ;Stops all navigations and pending resource fetches
	DocumentTitle => this.wv.DocumentTitle ;Returns the DocumentTitle of the current webpage
    AddHostObjectToScript(ObjName, Obj) => this.wv.AddHostObjectToScript(ObjName, Obj) ;Create object link between the WebView2 and the AHK Script
	RemoveHostObjectFromScript(ObjName) => this.wv.RemoveHostObjectFromScript(ObjName) ;Delete object link from the WebView2
	OpenDevToolsWindow() => this.wv.OpenDevToolsWindow() ;Opens DevTools for the current WebView2
	ContainsFullScreenElement => this.wv.ContainsFullScreenElement ;Returns true if the WebView contains a fullscreen HTML element
	AddWebResourceRequestedFilter(Uri, ResourceContext) => this.wv.AddWebResourceRequestedFilter(Uri, ResourceContext) ;Adds a URI and resource context filter for the WebResourceRequested event
	RemoveWebResourceRequestedFilter(Uri, ResourceContext) => this.wv.RemoveWebResourceRequestedFilter(Uri, ResourceContext) ;Removes a matching WebResource filter that was previously added for the WebResourceRequested event
	NavigateWithWebResourceRequest(Request) => this.wv.NavigateWithWebResourceRequest(Request) ;Navigates using a constructed CoreWebView2WebResourceRequest object
	CookieManager => this.wv.CookieManager ;Gets the CoreWebView2CookieManager object associated with this CoreWebView2
		GetCookies(Uri, Handler) => this.CookieManager.GetCookies(Uri, Handler) ;Gets a list of cookies matching the specific URI
		/**
		 * You have to first define the handler itself
		 * GetCookiesHandler(Msg) {}
		 * 
		 * Then you can call the Method
		 * MyWindow.GetCookies("https://google.com", GetCookiesHandlerFunc)
		**/

	Environment => this.wv.Environment ;Returns Map() of Environment settings
		BrowserVersionString => this.Environment.BrowserVersionString ;Returns the browser version info of the current CoreWebView2Environment, including channel name if it is not the stable channel
		FailureReportFolderPath => this.Environment.FailureReportFolderPath ;Returns the failure report folder that all CoreWebView2s created from this environment are using
		UserDataFolder => this.Environment.UserDataFolder ;Returns the user data folder that all CoreWebView2s created from this environment are using
		CreateWebResourceRequest(Uri, Method, PostData, Headers) => this.Environment.CreateWebResourceRequest(Uri, Method, PostData, Headers) ;Creates a new CoreWebView2WebResourceRequest object
		CreateCoreWebView2CompositionController(ParentWindow, Handler) => this.Environment.CreateCoreWebView2CompositionController(ParentWindow, Handler) ;Creates a new WebView for use with visual hosting
		CreateCoreWebView2PointerInfo() => this.Environment.CreateCoreWebView2PointerInfo() ;Returns Map() of a combined win32 POINTER_INFO, POINTER_TOUCH_INFO, and POINTER_PEN_INFO object
		GetAutomationProviderForWindow(Hwnd) => this.Environment.GetAutomationProviderForWindow(Hwnd) ;PRODUCES ERROR, REACH OUT TO THQBY
		CreatePrintSettings() => this.Environment.CreatePrintSettings() ;Creates the CoreWebView2PrintSettings used by the PrintToPdfAsync(String, CoreWebView2PrintSettings) method
		GetProcessInfos() => this.Environment.GetProcessInfos() ;Returns the list of all CoreWebView2ProcessInfo using same user data folder except for crashpad process
		CreateContextMenuItem(Label, IconStream, Kind) => this.Environment.CreateContextMenuItem(Label, IconStream, Kind) ;PRODUCES ERROR, REACH OUT TO THQBY
		CreateCoreWebView2ControllerOptions() => this.Environment.CreateCoreWebView2ControllerOptions() ;PRODUCES ERROR, REACH OUT TO THQBY
		CreateCoreWebView2ControllerWithOptions(ParentWindow, Options, Handler) => this.Environment.CreateCoreWebView2ControllerWithOptions(ParentWindow, Options, Handler) ;PRODUCES ERROR, REACH OUT TO THQBY -- I think the issue is part of the `CreateCoreWEbView2ControllerOptions()` method
		CreateCoreWebView2CompositionControllerWithOptions(ParentWindow, Options, Handler) => this.Environment.CreateCoreWebView2CompositionControllerWithOptions(ParentWindow, Options, Handler) ;PRODUCES ERROR, REACH OUT TO THQBY -- I think the issue is part of the `CreateCoreWEbView2ControllerOptions()` method
		CreateSharedBuffer(Size) => this.Environment.CreateSharedBuffer(Size) ;Create a shared memory based buffer with the specified size in bytes -- PRODUCES ERROR, REACH OUT TO THQBY

	Resume() => this.wv.Resume() ;Resumes the WebView so that it resumes activities on the web page
	IsSuspended => this.wv.IsSuspended ;Returns true if the WebView is suspended
	SetVirtualHostNameToFolderMapping(HostName, FolderPath, AccessKind) => this.wv.SetVirtualHostNameToFolderMapping(HostName, FolderPath, AccessKind) ;Sets a mapping between a virtual host name and a folder path to make available to web sites via that host name
	ClearVirtualHostNameToFolderMapping(HostName) => this.wv.ClearVirtualHostNameToFolderMapping(HostName) ;Clears a host name mapping for local folder that was added by SetVirtualHostNameToFolderMapping()
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
	CallDevToolsProtocolMethodForSession(SessionId, MethodName, ParametersAsJson, Handler) => this.wv.CallDevToolsProtocolMethodForSession(SessionId, MethodName, ParametersAsJson, Handler) ;Runs a DevToolsProtocol method for a specific session of an attached target
	StatusBarText => this.wv.StatusBarText ;Returns the current text of the WebView2 StatusBar
	Profile => this.wv.Profile ;Returns the associated CoreWebView2Profile object of CoreWebView2
	FaviconUri => this.wv.FaviconUri ;Returns the Uri as a string of the current Favicon. This will be an empty string if the page does not have a Favicon
	GetFavicon(Format, CompletedHandler) => this.wv.GetFavicon(Format, CompletedHandler) ;Get the downloaded Favicon image for the current page and copy it to the image stream
	
	Print(PrintSettings, Handler) => this.wv.Print(PrintSettings, Handler) ;Print the current web page asynchronously to the specified printer with the provided settings
		/**
		 * You have to create a handler to be able to pass to the Method
		 * PrintHandler(Msg) {}
		 * printSettings := MyWindow.CreatePrintSettings()
		 * printSettings.PrinterName := "HP Color LaserJet MFP M477fdn" ;this needs to match what you see in your 'Printers and Scanners' window
		 * MyWindow.Print(printSettings, PrintHandlerFunc)
		**/
	PrintToPdf(ResultFilePath, PrintSettings, Handler) => this.wv.PrintToPdf(ResultFilePath, PrintSettings, Handler) ;Print the current page to PDF with the provided settings
	ShowPrintUI(PrintDialogKind) => this.wv.ShowPrintUI(PrintDialogKind) ;Opens the print dialog to print the current web page. Browser printDialogKind := 0, System printDialogKind := 1
	PrintToPdfStream(PrintSettings, Handler) => this.wv.PrintToPdfStream(PrintSettings, Handler) ;Provides the PDF data of current web page for the provided settings to a Stream
	PostSharedBufferToScript(SharedBuffer, Access, AdditionalDataAsJson) => this.wv.PostSharedBufferToScript(SharedBuffer, Access, AdditionalDataAsJson) ;Share a shared buffer object with script of the main frame in the WebView
	MemoryUsageTargetLevel { ;0 = Normal, 1 = Low; Low can be used for apps that are inactive to conserve memory usage
		get => this.wv.MemoryUsageTargetLevel
		set => this.wv.MemoryUsageTargetLevel := Value
	}
    
    ;-------------------------------------------------------------------------------------------
	;Handler Assignments
	static PlaceholderHandler(Handler, ICoreWebView2, Args) {
		;MsgBox(handler, "WebviewWindow.PlaceholderHandler()", "262144")
	}

	;Controller
	ZoomFactorChanged(Handler) => this.ZoomFactorChangedHandler := this.wv.ZoomFactorChanged(Handler)
	MoveFocusRequested(Handler) => this.MoveFocusRequestedHandler := this.wv.MoveFocusRequested(Handler)
	GotFocus(Handler) => this.GotFocusHandler := this.wvc.GotFocus(Handler)
	LostFocus(Handler) => this.LostFocusHandler := this.wv.LostFocus(Handler)
	AcceleratorKeyPressed(Handler) => this.AcceleratorKeyPressedHandler := this.wv.AcceleratorKeyPressed(Handler)
	RasterizationScaleChanged(Handler) => this.RasterizationScaleChangedHandler := this.wv.RasterizationScaleChanged(Handler)

	;Core
	NavigationStarting(Handler) => this.NavigationStartingHandler := this.wv.NavigationStarting(Handler)
	ContentLoading(Handler) => this.ContentLoadingHandler := this.wv.ContentLoading(Handler)
	SourceChanged(Handler) => this.SourceChangedHandler := this.wv.SourceChanged(Handler)
	HistoryChanged(Handler) => this.HistoryChangedHandler := this.wv.HistoryChanged(Handler)
	NavigationCompleted(Handler) => this.NavigationCompletedHandler := this.wv.NavigationCompleted(Handler)
	ScriptDialogOpening(Handler) => this.ScriptDialogOpeningHandler := this.wv.ScriptDialogOpening(Handler)
	PermissionRequested(Handler) => this.PermissionRequestedHandler := this.wv.PermissionRequested(Handler)
	ProcessFailed(Handler) => this.ProcessFailedHandler := this.wv.ProcessFailed(Handler)
	WebMessageReceived(Handler) => this.WebMessageReceivedHandler := this.wv.WebMessageReceived(Handler)
	NewWindowRequested(Handler) => this.NewWindowRequestedHandler := this.wv.NewWindowRequested(Handler)
	DocumentTitleChanged(Handler) => this.DocumentTitleChangedRequested := this.wv.DocumentTitleChanged(Handler)
	ContainsFullScreenElementChanged(Handler) => this.ContainsFullScreenElementChangedHandler := this.wv.ContainsFullScreenElementChanged(Handler)
	WebResourceRequested(Handler) => this.WebResourceRequestedHandler := this.wv.WebResourceRequested(Handler)
	WindowCloseRequested(Handler) => this.WindowCloseRequestedHandler := this.wv.WindowCloseRequested(Handler)
	WebResourceResponseReceived(Handler) => this.WebResourceResponseReceivedHandler := this.wv.WebResourceResponseReceived(Handler)
	DOMContentLoaded(Handler) => this.DOMContentLoadedHandler := this.wv.DOMContentLoaded(Handler)
	TrySuspend(Handler) => this.TrySuspendHandler := this.wv.TrySuspend(Handler)
	FrameCreated(Handler) => this.FrameCreatedHandler := this.wv.FrameCreated(Handler)
	DownloadStarting(Handler) => this.DownloadStartingHandler := this.wv.DownloadStarting(Handler)
	ClientCertificateRequested(Handler) => this.ClientCertificateRequestedHandler := this.wv.ClientCertificateRequested(Handler)
	IsMutedChanged(Handler) => this.IsMutedChangedHandler := this.wv.IsMutedChanged(Handler)
	IsDocumentPlayingAudioChanged(Handler) => this.IsDocumentPlayingAudioChangedHandler := this.wv.IsDocumentPlayingAudioChanged(Handler)
	IsDefaultDownloadDialogOpenChanged(Handler) => this.IsDefaultDownloadDialogOpenChangedHandler := this.wv.IsDefaultDownloadDialogOpenChanged(Handler)
	BasicAuthenticationRequested(Handler) => this.BasicAuthenticationRequestedHandler := this.wv.BasicAuthenticationRequested(Handler)
	ContextMenuRequested(Handler) => this.ContextMenuRequestedHandler := this.wv.ContextMenuRequested(Handler)
	StatusBarTextChanged(Handler) => this.StatusBarTextChangedHandler := this.wv.StatusBarTextChanged(Handler)
	ServerCertificateErrorDetected(Handler) => this.ServerCertificateErrorDetectedHandler := this.wv.ServerCertificateErrorDetected(Handler)
	ClearServerCertificateErrorActions(Handler) => this.ClearServerCertificateErrorActionsHandler := this.wv.ClearServerCertificateErrorActions(Handler)
	FaviconChanged(Handler) => this.FaviconChangedHandler := this.wv.FaviconChanged(Handler)
	LaunchingExternalUriScheme(Handler) => this.LaunchingExternalUriSchemeHandler := this.wv.LaunchingExternalUriScheme(Handler)
    
	;ExecuteScriptCompleted
	ExecuteScriptCompleted(Handler) => this.ExecuteScriptCompletedHandler := WebView2.Handler(Handler)

	/**
	 * The following event handlers are commented out for the time being.
	 * Their assignments are not accurate and cannot be used directly,
	 * I'm leaving them here for easy tracking of event handlers and
	 * I may revisit fixing them in the future.  
	**/
	/*
	;DownloadOperation
	BytesReceivedChanged(Handler) => this.BytesReceivedChangedHandler := this.do.BytesReceivedChanged(Handler)
	EstimatedEndTimeChanged(Handler) => this.EstimatedEndTimeChangedHandler := WebView2.Handler(Handler)
	StateChanged(Handler) => this.StateChangedHandler := WebView2.Handler(Handler)

	;Environment
	NewBrowserVersionAvailable(Handler) => this.NewBrowserVersionAvailableHandler := this.wv.NewBrowserVersionAvailable(Handler)
	BrowserProcessExited(Handler) => this.BrowserProcessExitedHandler := this.wv.BrowserProcessExited(Handler)
	ProcessInfosChanged(Handler) => this.ProcessInfosChangedHandler := this.wv.ProcessInfosChanged(Handler)

	;Frame
	FrameNameChanged(Handler) => this.FrameNameChangedHandler := this.wv.NameChanged(Handler)
	FrameDestroyed(Handler) => this.FrameDestroyedHandler := this.wv.FrameDestroyed(Handler)
	FrameNavigationStarting(Handler) => this.FrameNavigationStartingHandler := this.wv.FrameNavigationStarting(Handler)
	FrameNavigationCompleted(Handler) => this.FrameNavigationCompletedHandler := this.wv.FrameNavigationCompleted(Handler)
	FrameContentLoading(Handler) => this.FrameContentLoadingHandler := this.wv.FrameContentLoading(Handler)
	FrameDOMContentLoaded(Handler) => this.FrameDOMContentLoadedHandler := this.wv.FrameDOMContentLoaded(Handler)
	FrameWebMessageReceived(Handler) => this.FrameWebMessageReceivedHandler := this.wv.FrameWebMessageReceived(Handler)
	FramePermissionRequested(Handler) => this.FramePermissionRequestedHandler := this.wv.FramePermissionRequested(Handler)

	;Profile
	ClearBrowsingDataAll(Handler) => this.ClearBrowsingDataAllHandler := this.wv.ClearBrowsingDataAll(Handler)

	;CompositionController
	CursorChanged(Handler) => this.CursorChangedHandler := this.wv.CursorChanged(Handler)

	;ContextMenuItem
	CustomItemSelected(Handler) => this.CustomItemSelectedHandler := this.wv.CustomItemSelected(Handler)

	;DevToolsProtocolEventReceiver
	DevToolsProtocolEventReceived(Handler) => this.DevToolsProtocolEventReceivedHandler := this.wv.DevToolsProtocolEventReceived(Handler)

	;WebResourceResponseView
	GetContent(Handler) => this.GetContentHandler := this.wv.GetContent(Handler)
	*/
}