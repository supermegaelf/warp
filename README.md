### Installation:

```bash
bash <(curl -s https://raw.githubusercontent.com/supermegaelf/warp/main/warp.sh)
```

Добавить в конце секции `OUTBOUNDS`:

```
    {
      "tag": "warp-out",
      "protocol": "socks",
      "settings": {
        "servers": [
          {
            "port": 40000,
            "address": "127.0.0.1"
          }
        ]
      }
    }
```

> [!NOTE]
> Добавить при необходимости:

```
"tiktok.com"
```

Добавить в секцию `RULES` (после `BLOCK`):

```
      {
        "type": "field",
        "domain": [
          "tiktok.com"
        ],
        "outboundTag": "warp-out"
      },
```
