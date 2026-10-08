# Reading and keyboard use

Contrast is the default appearance for a new set of preferences. **Black** uses white text on black; **White** uses black text on white. That primary text/background pair has a 21:1 contrast ratio. This does not claim that every control has been independently audited or that the whole app meets a particular accessibility standard.

Classic and Custom appearances remain available. Custom shows the contrast ratio of the chosen color pair. Reading text can be enlarged without enlarging all interface chrome. Selection uses shape and an edge marker as well as color. The app responds to macOS Reduce Motion and Reduce Transparency preferences.

The Saved Shelf now exposes every saved word through **Show all**, rather than hiding older entries after the first twelve. It holds up to 200 words and explains when it is full; adding another cannot silently remove an existing word. **Clear history** removes recent/popular lookup activity and Back/Forward entries, including activity from a lookup already finishing in the background. It retains the current displayed result and saved words; it is not an erase-all-data control.

| Action | Keyboard command |
| --- | --- |
| Focus search | Command-L |
| Commit the current lookup | Return |
| Paste and search | Shift-Command-V |
| Open Quick Lookup | Shift-Command-Space |
| Enlarge / reduce / reset reading text | Command-Plus / Command-Minus / Command-0 |
| Clear the desk and lookup history | Shift-Command-K |

The current evaluation pass exercised Black and White appearance, search, lookup modes, saved preferences, quitting, and relaunching on an Apple Silicon Mac. Automated checks cover appearance values and relevant interaction state. A full spoken VoiceOver pass and testing on other physical Macs remain outstanding.

Accessibility is an ongoing product requirement. Please report missing labels, lost focus, ambiguous selection, clipping, or a keyboard path that does not work for you; see [privacy and support](PRIVACY.md).
