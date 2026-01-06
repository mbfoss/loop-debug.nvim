<p align="center">
  <strong>Debugging extension for loop.nvim.</strong>
</p>

<p align="center">
  <a href="https://neovim.io/">
    <img src="https://img.shields.io/badge/Neovim-0.10+-blueviolet.svg?style=flat-square&logo=neovim" alt="Neovim 0.10+">
  </a>
  <a href="https://github.com/mbfoss/loop.nvim/blob/main/LICENSE">
    <img src="https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square" alt="MIT License">
  </a>
</p>

---

> [!WARNING]
> **Work in Progress**: This plugin is in early development and not ready for public release yet.

# loop-debug.nvim

Debugging extension for [loop.nvim](https://github.com/mbfoss/loop.nvim). Provides DAP integration via `debug` task types.

## Features

- **Clean and useful UI integration**
- **Breakpoints**
- **Watch expressions** 
- **Callstack** 
- **Debugger console (REPL)** 
- **Debuggee output (With run-in-terminal support)** 
- **Multisession support**

> [!WARNING]
> This plugin uses it's own DAP implementation and approach to configuration and does not require or depend on `nvim-dap`.

## Requirements

- Neovim >= 0.10
- [loop.nvim](https://github.com/mbfoss/loop.nvim)

## Installation

**With lazy.nvim**
```lua
{
    "mbfoss/loop-debug.nvim"
}
```

**With packer.nvim**
```lua
use {
    'mbfoss/loop-debug.nvim',
}
```

## Contributing

Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.

## License

Distributed under the MIT License. See [LICENSE](LICENSE) for details.