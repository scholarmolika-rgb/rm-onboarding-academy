# SecureQuestion

The secure question screen shows one assessment question at a time with a server-driven countdown and a transparent note of recorded activity.

Use it only inside a gate assessment (Gate 1, Gate 2, Final). Layout: title "Question N of M" with the seconds left in the `code` style, a `ds-bar` countdown that turns `crit` under 15 seconds, the question with a module `kind` tag, options as full-width selectable rows, a single primary action ("Save and next" / "Save and submit") that stays disabled until an option is chosen, and a `caption` line on the right that tells the trainee exactly what has been recorded ("No unusual activity recorded", or "Recorded: left screen 1× · copy/paste 1×").

Rules: never show a back button; never show study material beside it (the page collapses to this single panel while a test is open); never colour the recorded-activity note as an error, because signals are evidence for a mentor, not a verdict. Copy for the honour declaration and hold states lives in the prototype and in docs/ASSESSMENT_INTEGRITY.md. The consumer provides the question, options, seconds left and recorded events, all from `serve_question`.
