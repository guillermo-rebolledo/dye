# Identity outside the dial rail: research notes

Research checked September 10, 2026. This is a proposal, not an implemented change or a usability-test result.

## Evidence from primary sources

| Source | Documented guidance or behavior | Implication for Dye (design inference) |
| --- | --- | --- |
| [Apple HIG: Scroll views](https://developer.apple.com/design/human-interface-guidelines/scroll-views) | Support familiar scrolling. Same-orientation nested scroll views can produce unpredictable interactions. Partial edge content can signal more content offscreen. | Remove the stock browser from the horizontal adjustment-navigation surface. Keep a continuous dial rail, with a partial next dial signaling navigation. The warning concerns nested scrolling specifically; it does not prove the cause of Dye's current gesture interception. |
| [Apple HIG: Gestures](https://developer.apple.com/design/human-interface-guidelines/gestures/) | Gestures should match expectations; custom gestures should be distinct, discoverable, and accompanied by another way to perform important actions. | Give identity a visible tap target. Avoid requiring a swipe through stock choices, an end-of-strip escape gesture, or a long press to return to adjustments. |
| [Apple HIG: Layout](https://developer.apple.com/design/human-interface-guidelines/layout) | Position and alignment communicate importance. Group related controls with sufficient space. Use progressive disclosure for collections that cannot be fully displayed. Adapt to orientation, text size, and safe areas. | Present identity as its own persistent, labeled section immediately above the dials. Show the active selection there; disclose the catalog on demand. Separation communicates that stock/output establishes the image's character while dials refine it. |
| [Apple HIG: Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets) | Sheets support scoped tasks related to the current context. iOS sheets can be nonmodal. A medium detent can disclose content progressively; a resizable sheet should expose a grabber. | Open stock selection as a dedicated sheet or temporary browser in the deck, leaving image preview context available. Keep the identity summary visible in the resting editor; do not make the sheet its only presence. |
| [Adobe Lightroom mobile: Apply profiles](https://helpx.adobe.com/lightroom/mobile/adjust-light-and-color/apply-profiles.html) | Adobe describes profiles as the foundation for color and tonality. Applying a profile does not change the other edit-slider values. Its documented workflow opens Profiles, browses thumbnail categories, and applies a selection. | This supports separating foundational look selection from continuous adjustments conceptually. Dye can give that foundation more prominence than Lightroom does by showing its current identity persistently. Adobe's behavior is an analogy, not a requirement that Dye stock switches preserve every value. |

## Recommended arrangement

Use a fixed identity row at the top of the editing deck, between the photo and adjustment controls. Preserve the film character with a compact stock thumbnail/swatch, the full stock name as the strongest text, and an explicit disclosure indicator. If output mode is part of identity, show its current Scan/Print state alongside it with a separately named tap target. Keep both targets outside the rail's hit-testing and gesture region.

Below it, retain one horizontally scrolling rail containing adjustment dials only. Selecting identity opens a focused stock/output browser; selecting a stock updates the image and the fixed summary. Returning to controls restores the same selected dial and rail offset when valid. If a stock removes the selected adjustment, choose the nearest valid dial predictably. That reconciliation rule must respect existing engine behavior.

The journey becomes **choose the image's identity → refine it with dials → revisit identity whenever needed → export**. The identity remains an always-visible statement of what is being made, even when the user has scrolled to late-stage controls.

## Alternatives and tradeoffs

| Placement | Benefit | Cost |
| --- | --- | --- |
| Fixed identity row above dials — recommended | Visible, reachable, clearly separates foundation from adjustment; no identity region inside rail | Needs vertical space; fit within the existing deck before reducing preview height |
| Identity in top app bar | Persistent and frees deck height | Farther from editing controls; competes with navigation and image actions; long stock names may truncate |
| Small badge floating over the photo | Saves deck space | Can cover image details and look like passive metadata; contrast varies with image; easy to understate the core feature |

Avoid keeping identity pinned at one end of the rail: it still occupies the rail's gesture path and makes the row a mixed navigation/control surface. Avoid a second permanent horizontal stock carousel: it adds another scrolling region and gives too much resting space to unselected choices.

## Validate before implementation is considered finished

- Users can identify and change the active stock without searching the rail.
- Left/right swipes across the dial rail navigate continuously, with no identity takeover or dead zone.
- Returning from the browser preserves dial selection/position where supported by the chosen stock.
- The current stock stays readable while scrolling to the last dial; output state is unambiguous.
- The layout fits small phones, landscape, and accessibility text sizes without hiding the identity or obstructing the preview unnecessarily.
- VoiceOver encounters identity before adjustments, names its current value, and offers an explicit activation action. Motion is optional for understanding the transition.

These are acceptance criteria for a prototype review, not findings from observed users. Exact row height, typography, and preview-space tradeoffs require inspection in Dye's actual editor.
