# GEM Navigator first two screens

## Goal

Implement the first two frames of the supplied Navigator App UI design as a self-contained Flutter flow.

## Screens

1. Museum map: GEM header, level title, stylized map canvas, Food and Gift shop category pills, layers and recenter controls, and a route entry action.
2. Pinned location: modal detail sheet over the map with artifact title, location metadata, supporting copy, and a Start route action.

## Interaction

- Food and Gift shop pills toggle selected state.
- The route entry action opens the pinned-location sheet.
- The map canvas is tappable and opens the same sheet.
- Start route dismisses the sheet.

## Architecture and testing

The map is a CustomPainter inside a reusable screen shell. The pinned location is a showModalBottomSheet so the dimmed map remains visible behind it. Widget tests verify initial content, category interaction, sheet presentation, and dismissal.

