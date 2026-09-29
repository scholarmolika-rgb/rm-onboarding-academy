# Button

Buttons trigger one action; the primary variant marks the single most important action in a view.

Use `ds-btn--primary` once per panel for the action that moves the journey forward ("Start assessment", "Pass to next phase"). Secondary `ds-btn` for alternatives ("Repeat selected modules"). Labels are verbs that say exactly what happens. Disable a button when its precondition is unmet (all questions answered, notes ≥ 30 characters) rather than showing an error after the click. The consumer provides the label and the click handler.
