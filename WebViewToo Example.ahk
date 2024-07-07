;Environment Controls
;///////////////////////////////////////////////////////////////////////////////////////////
#Requires Autohotkey v2
#SingleInstance Force
#Include AHK Resources/WebView2.ahk
#Include AHK Resources/WebViewToo.ahk

ScriptPID := DllCall("GetCurrentProcessId")
GroupAdd("ScriptGroup", "ahk_pid" ScriptPID)
;///////////////////////////////////////////////////////////////////////////////////////////

;Create the WebviewWindow/GUI
;///////////////////////////////////////////////////////////////////////////////////////////
MyWindow := WebViewToo(,,, True) ;You can omit the final parameter or switch 'True' to 'False' to use a Native Window's Titlebar
MyWindow.OnEvent("Close", (*) => ExitApp())
MyWindow.Load("Pages/index.html")
MyWindow.Debug()
MyWindow.AddHostObjectToScript("ahkButtonClick", {func:WebButtonClickEvent})
MyWindow.AddCallBackToScript("CopyGlyphCode", CopyGlyphCodeEvent)
MyWindow.AddCallBackToScript("Tooltip", WebTooltipEvent)
MyWindow.AddCallbackToScript("ahkFormSubmit", FormSubmitHandler)
MyWindow.Show("w1200 h800 Center", "WebViewToo Example")
;///////////////////////////////////////////////////////////////////////////////////////////

;Hotkeys
;///////////////////////////////////////////////////////////////////////////////////////////
#HotIf WinActive("ahk_group ScriptGroup")
F1:: {
    MsgBox(MyWindow.Title)
    MyWindow.Title := "New Title!"
    MsgBox(MyWindow.Title)
}

F2:: {
    MyWindow.PostWebMessageAsString("Hello?")
}

F3:: {
    MyWindow.SimplePrintToPdf()
}
#HotIf
;///////////////////////////////////////////////////////////////////////////////////////////

;Web Functions
;///////////////////////////////////////////////////////////////////////////////////////////
WebButtonClickEvent(button) {
    MsgBox(button)
}

CopyGlyphCodeEvent(WebView, Title) {
	GlyphCode := "<span class='glyphicon glyphicon-" Title "' aria-hidden='true'></span>"
	MsgBox(A_Clipboard := GlyphCode, "OuterHTML Copied to Clipboard")
}

WebTooltipEvent(WebView, Msg) {
    ToolTip(Msg)
    SetTimer((*) => ToolTip(), -1000)
}

/**
 * There's something weird about calling WebViewToo methods from within
 * a defined WebView2 callback. At this time, we actually need to forward
 * function call through a `SetTimer()` call to make release it from the ComObj.
 * 
 * Example: `FormSubmitHandler()` is the callback, if we tried to call `MyWindow.GetFormData()`
 * from the callback, it actually stalls out and does not execute properly.
 * 
 * I will continue working on a better way to handle these
**/
;There's something weird about calling WebViewToo methods from within
;a WebView2 callback. At this time, we actually need to forward the function
;through a `SetTimer()` call to make it asynchronous and allow it to work
;
FormSubmitHandler(WebView, Form) => SetTimer((*) => FormSubmitEvent(WebView, Form), -1)
FormSubmitEvent(WebView, Form) {
    FormInfo := MyWindow.GetFormData(Form)
    MsgBox(WebViewToo.forEach(FormInfo))
}
;///////////////////////////////////////////////////////////////////////////////////////////