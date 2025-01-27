# WebViewToo
Allows for use of the WebView2 Framework within AHK to create Web-based GUIs

## NOTE: THIS UPDATE IS NOT BACKWARDS COMPATIBLE.
- If you have current scripts using this library, you will almost certainly need to update your scripts.

### Major Changes
- Overhauled methods for managing window sizing as well as borders/edges.
- In compiled scripts we can now load webpages without needing to write the files to the disk.
- Provided ability to open the webpage to all of AutoHotkey's native functions such as `MsgBox()`.
- The `QueryPage()` and `qp()` methods have been removed. Instead you should now use `ExecuteScript()`.
	
### Minor Changes
- Updated the `CreateFileFromResource()` method to accept an output file path for more flexibility.
  - This method is no longer called during the constructor.
- Renamed `EscapeHTML()` method to `EscapeHtml()`.
- Renamed `EscapeJS()` method to `EscapeJavaScript()`.
- Reworked the `ForEach()` static method to maintain functionality that was removed from `WebView2.ahk`.
- Added `RemoveCallbackFromScript()` method to work alongside previously added `AddCallbackToScript()` method.
- Streamlined the `Load()` method.
- Added guard clauses to various methods for improved performance.
- Reworked the `SimplePrintToPdf()` function so that it continues to work with updates to `WebView2.ahk`.
- Some garbage collection has been added as an `OnExit()` callback.
- Added `Bounds()` method for easier handling of the WebView2 bounding rect.
- The `DefaultBackgroundColor` property now returns the color code in RGB format.
- The `IsNonClientRegionSupportEnabled`property has been added and is enabled during the constructor.

### Bug Fixes
- Scripts no longer stall and provide error codes on exit due to registered event handlers.
