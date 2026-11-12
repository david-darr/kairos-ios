# Screens to photograph

One file per area: `<area>.txt`. Each line is a picture name, then the launch arguments.

```
vault -kDebugView library.vault
vault-light -kDebugView library.vault -kAppearance light
```

Lines starting with `#` are skipped. The build saves each picture as `<area>-<name>.png`.
