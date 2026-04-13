### Installation:

```bash
bash <(curl -s https://raw.githubusercontent.com/supermegaelf/warp/main/warp.sh)
```

Добавить в конце секции `OUTBOUNDS`:

```
    {
      "tag": "warp-out",
      "protocol": "freedom",
      "settings": {
        "domainStrategy": "UseIP"
      },
      "streamSettings": {
        "sockopt": {
          "interface": "warp"
        }
      }
    }
```

> [!NOTE]
> Добавить при необходимости:

```
"domain:tiktok.com"
"domain:gemini.google.com"
```

Добавить в секцию `RULES` (после `BLOCK`):

```
      {
        "type": "field",
        "domain": [
          "domain:tiktok.com",
          "domain:gemini.google.com"
        ],
        "outboundTag": "warp-out"
      },
```
