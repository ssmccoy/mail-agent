# Guidelines

commits:
    headline:
        len: <= 55
        style: imperitive
        format: "<component>: objective"
    body:
        len: <= 72
        style: terse, technical
        include: reason for change
        exclude: code references, change details

compoents:
    bin/mail-agent-(.\*)
    tests
    mutt

always:
    - TDD
    - KISS
    - MCC(f) ≤ 10

ask:
    - dependencies
    - new components
