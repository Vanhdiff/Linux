# Block Trade

Goal:

Protect traders from violating discipline rules.

There are four protection layers.

Layer 1

Rule Engine

Layer 2

Application Guard

Layer 3

Windows Guard

Layer 4

MT5 Protection

Current implementation:

Layer1
≈ 80%

Layer2
≈ 70%

Layer3
0%

Layer4
≈ 40%

Target state machine:

NORMAL

↓

WARNING

↓

TEMPORARY_BLOCK

↓

FULL_DAY_BLOCK

↓

RESOLVED

↓

ARCHIVED