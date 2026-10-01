# Elpris for Omarchy

**Nord Pool electricity spot price, in your bar.** The current price at a
glance, color-coded against today's range, with an hourly chart for today and
tomorrow so you know when to run the dishwasher.

## Features

- Current spot price in the bar, updated every 15 minutes (market resolution)
- Click for a panel with today's hourly price chart — cheap hours green,
  expensive hours orange, a dot marking the current hour
- Tomorrow's chart appears automatically once Nord Pool publishes (~13:00)
- Today's low / average / high at a glance
- Hover any bar to read the exact hour and price
- All four Swedish price zones (SE1–SE4), configurable in settings
- Prices in kr or öre, with 0, 1 or 2 decimals in öre mode
- Negative prices keep their sign, including the hours that round to zero
- Zero configuration to start, no API key, no account — data from the free
  [elprisetjustnu.se](https://www.elprisetjustnu.se) API
- Theme aware — follows your Omarchy theme like the built-in widgets

## Install

```bash
omarchy plugin add https://github.com/antoniowav/omarchy-elpris.git --enable
```

## Remove

```bash
omarchy plugin remove io.github.antoniowav.elpris
```

## Dependencies

None beyond what Omarchy ships: `curl` for fetching prices, rendered by the
Omarchy Quattro shell. No accounts, no API keys, no telemetry.

## Configure

Click the widget, then the gear in the panel's top-right corner: pick your
price zone (SE1 Luleå, SE2 Sundsvall, SE3 Stockholm/Göteborg, SE4 Malmö)
and unit (kr or öre), then save. Öre mode adds a decimals control — `14`,
`14,1` or `14,08` — which defaults to whole öre. Settings can also be set
from a terminal:

```bash
omarchy bar set io.github.antoniowav.elpris zone SE4
omarchy bar set io.github.antoniowav.elpris unit öre
omarchy bar set io.github.antoniowav.elpris decimals 2
```

Middle-click the widget to force a refresh.

## Data

Prices come from the free [elprisetjustnu.se](https://www.elprisetjustnu.se)
API. Elpriser tillhandahålls av Elpriser just nu. Prices are spot prices
excluding VAT, grid fees, and your supplier's markup.

## License

MIT
