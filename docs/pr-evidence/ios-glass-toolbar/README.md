# iOS editor toolbar refinement

The bottom controls open editing tools, a photo picker, and export sheets. They therefore behave as toolbar actions, without a persistent selected-tab state. Each action has a visible SF Symbol and text label, with a minimum 44-point touch target. One regular Liquid Glass surface groups the tools; the existing opaque accessibility and older-iOS material fallbacks remain in place.

Apple references informing this change:

- [Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars): distinguish section navigation from actions; use clear labels and familiar SF Symbols. Clock is Apple's example of actual top-level tab navigation.
- [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars): controls act on the current content. The editor follows the action-oriented approach familiar from Photos.
- [Materials](https://developer.apple.com/design/human-interface-guidelines/materials): reserve Liquid Glass for the functional layer above content. Remove the nested glass selection lens.
- [UI design tips](https://developer.apple.com/design/tips/): preserve legibility and touch targets of at least 44 by 44 points.

The main screen now uses a SwiftUI navigation bar for its title and Settings button. Stage selection has a visible disclosure chevron and system text styles. Toolbar labels scale with Dynamic Type; accessibility sizes use a native More menu for secondary actions; the deck grows to accommodate them. Landscape editing controls can scroll vertically.

Screenshots are direct `simctl io booted screenshot` captures from the iPhone 17 Pro simulator running iOS 26.5 on this Mac. The flower image is a sample already in the simulator's photo library.
