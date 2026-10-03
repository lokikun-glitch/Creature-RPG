class_name BattleSide
## Which side of a battle something belongs to. Lives in its own dependency-free script so all
## battle scripts share one type (an enum inside a script that's part of a dependency cycle
## confuses GDScript's type checker).

enum Side { PLAYER, WILD }
