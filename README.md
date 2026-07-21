# Codex Level

Codex Level is a small macOS menu bar app that turns your lifetime Codex usage into a visible level and progress bar.

It shows:

- your Codex profile name, lifetime Token usage, and current streak;
- your current Codex plan as a colored diamond beside your name;
- your current level and progress toward the next level;
- QQ-style star, moon, sun, and crown level badges;
- weekly Codex usage, reset time, and available banked resets;
- automatic refresh every minute, plus manual refresh;
- a global `⌥L` shortcut that opens or closes the panel from anywhere.

## Built with Codex and GPT-5.6

**GPT-5.6 helped me with everything.**

I built Codex Level with Codex and GPT-5.6—from designing the QQ-inspired progression system and plan diamonds to implementing usage tracking, polishing the macOS UI, writing tests, and debugging real-world data edge cases.

## Preview

<p align="center">
  <img src="assets/codex-level-popover.png" alt="Codex Level showing a real Lv.9 account with lifetime Token usage, level progress, and weekly usage" width="360">
</p>

## Keyboard shortcut

Press `⌥L` (Option + L) anywhere in macOS to toggle the Codex Level panel. Clicking the menu bar item still works normally.

## Plan diamonds

Codex Level now reads the plan type returned with weekly usage and displays a decorative diamond beside the profile name.

<table>
  <thead>
    <tr>
      <th>Go</th>
      <th>Plus</th>
      <th>Pro 5x</th>
      <th>Pro 20x</th>
    </tr>
  </thead>
  <tbody>
    <tr align="center">
      <td><img src="Sources/CodexLevelApp/Resources/plan-diamond-go.png" alt="Green Go plan diamond with a lightning bolt" width="88"></td>
      <td><img src="Sources/CodexLevelApp/Resources/plan-diamond-plus.png" alt="Yellow Plus plan diamond" width="88"></td>
      <td><img src="Sources/CodexLevelApp/Resources/plan-diamond-pro5x.png" alt="Purple Pro 5x plan diamond" width="88"></td>
      <td><img src="Sources/CodexLevelApp/Resources/plan-diamond-pro20x.png" alt="Red Pro 20x plan diamond" width="88"></td>
    </tr>
    <tr align="center">
      <td>💚 Green diamond</td>
      <td>💛 Yellow diamond</td>
      <td>💜 Purple diamond</td>
      <td>❤️ Red diamond</td>
    </tr>
  </tbody>
</table>

The plan diamond is independent from the QQ-style level. The diamond represents the current subscription plan; stars, moons, suns, and crowns represent lifetime Token usage. Unknown plan values are not guessed, so the app simply hides the diamond if Codex returns a plan it does not recognize.

## The QQ level idea

Yes, this project is openly inspired by QQ's classic level system. The numeric level is decomposed into the familiar progression:

- ⭐ = 1 level
- 🌙 = 4 levels
- ☀️ = 16 levels
- 👑 = 64 levels

For example, Lv.9 is shown as `🌙🌙⭐`.

This is an unofficial, non-commercial fan project. It is not affiliated with or endorsed by Tencent or QQ. The QQ-style level display uses ordinary Unicode emoji, while the plan diamonds are separate decorative artwork included with Codex Level. QQ and related marks belong to their respective owners.

## Requirements

- macOS 13 or later
- Swift 6
- an existing local Codex login

Codex Level reads the local Codex authentication state solely to request account data. It does not log, display, or upload access and refresh tokens.

## Run locally

```sh
swift run CodexLevel
```

Run the test suite with:

```sh
swift test
```

## Data and compatibility

Codex Level reads profile and usage information from Codex interfaces used by the local Codex experience. The weekly usage response also supplies the plan type used by the diamond system. These interfaces may change without notice, so future Codex updates can temporarily break data loading or plan detection.

The OAuth weekly-usage and banked-reset implementations were adapted from the Codex provider in [steipete/CodexBar](https://github.com/steipete/CodexBar), which is distributed under the MIT License. CodexBar deserves the credit for proving these data paths in a real macOS menu bar product. Its copyright and license notice are preserved in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Status

This is an early MVP. It has no cloud backend, database, analytics, third-party dependencies, leaderboard, or multi-provider support.

## License

[MIT](LICENSE)
