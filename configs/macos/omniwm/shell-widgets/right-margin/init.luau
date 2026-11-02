-- Space after the last widget on the right. With the menu bar hidden under
-- OmniShell, macOS draws its screen-recording indicator as a dot in the
-- top-right corner, over the clock; this keeps the clock clear of it (with the
-- bar's own 6 pt between widgets, everything moves 16 pt left).
function render(ctx: Context)
    return ui.box{ w = 10, h = 1 }
end
