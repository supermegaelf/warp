### Installation:

```bash
bash <(curl -s https://raw.githubusercontent.com/supermegaelf/warp/main/warp.sh)
```

Добавить в конце секции `RULES`:

```
      {
        "outboundTag": "WARP",
        "domain": [
          "full:*.vsco.co"
        ],
        "type": "field"
      }
```

> [!NOTE]
> Добавить при необходимости:

```
"geosite:meta"
```

Добавить в конце секции `OUTBOUND`:

```
    {
      "tag": "WARP",
      "protocol": "socks",
      "settings": {
        "servers": [
          {
            "address": "127.0.0.1",
            "port": 40000
          }
        ]
      }
    }
```
