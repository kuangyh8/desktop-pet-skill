# desktop-pet skill

一个用于在 macOS 上制作「桌宠 / 桌面宠物」的 Codex 技能：透明、无边框、置顶的 Electron
窗口，只显示角色本身，支持点击切换立绘、拖动和右键菜单，并附带人物抠图流程。

技能本体在 [skills/desktop-pet](skills/desktop-pet)。

## 安装

用 Codex 的 skill-installer：

```bash
python3 ~/.codex/skills/.system/skill-installer/scripts/install-skill-from-github.py \
  --repo kuangyh8/desktop-pet-skill \
  --path skills/desktop-pet
```

或手动复制：

```bash
mkdir -p ~/.codex/skills
cp -R skills/desktop-pet ~/.codex/skills/desktop-pet
```

安装后新开一轮对话即可使用，也可用 `$desktop-pet` 显式调用。

## 内容

- `SKILL.md`：桌宠制作的完整工作流和关键经验
- `references/macos-electron-pet.md`：Electron 透明窗口、拖动、右键菜单、位置记忆的配方
- `references/background-removal.md`：用 macOS Vision 给角色图抠透明背景
- `scripts/cutout.swift`：可复用的 Vision 抠图工具
