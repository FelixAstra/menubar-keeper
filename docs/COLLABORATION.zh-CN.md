# MenuBarKeeper 两人协作手册

这份文档写给两个人：仓库所有者 **FelixAstra**（下称"你"）和协作者 **642335425-lab**（下称"她"）。

它讲的是**怎么配合**——谁在什么时候做什么、怎么不互相踩。至于"这个项目本身有哪些规矩"（不许加依赖、`VERSION` 不能碰、文案要写两份语言等），在 [CONTRIBUTING.md](../CONTRIBUTING.md) 里，这份手册不重复。

## 一句话原则

> **一人一个分支，一个分支一件事，一切都经 PR 进 `main`。**

三条推论，后面所有流程都是它们的展开：

1. **`main` 是只出不进的成品线。** 它已有分支保护：任何改动必须走 PR，且 CI 的 `Build` 任务必须通过。
2. **分支是各自的工作台。** 你在自己的分支上怎么折腾（包括让 AI 反复重写）都不影响对方。
3. **PR 是交接点。** 代码、理由、验证结果都通过 PR 交付，不在微信/聊天里口头同步。

## 一、双方的配置差异（先搞清楚这个）

| | 你（FelixAstra） | 她（642335425-lab） |
|---|---|---|
| GitHub 权限 | Admin | Write |
| 能推 `main` 吗 | 能（但别这么做） | **不能**，会被保护规则拦下 |
| 能改仓库设置吗 | 能 | 不能 |
| 用的 AI 助手 | WorkBuddy | ChatGPT |

**权限的实际含义**：她能建分支、推分支、开 PR、评论、建 Issue；不能推 `main`、不能合并（除非你允许）、不能改设置。这个边界是保护规则给的，不是靠自觉。

**AI 助手的能力差异，是你们最容易踩的坑**，必须说清楚：

- **WorkBuddy（你这边）**能直接读写本机文件、执行 `git`、调用 GitHub 接口。所以你可以让 AI 一路跑到"分支已推送、PR 已创建"，你只在合并这种不可逆节点上点一下确认。
- **ChatGPT 网页版看不到她的本地仓库。** 它只能对着她贴进去的代码片段给建议，改完的文件要她自己保存，`git` 命令也要她自己敲。**AI 说改完了 ≠ 文件真的改了。**
- 她若用 ChatGPT 桌面版（能读本机文件）、Codex 或 Copilot，情况会好一些，但**推送和开 PR 这两步仍然由她本人执行**——AI 不该拿她的凭据去推仓库。

结论：**她那一侧，AI 负责"写"，人负责"落盘、验证、推送"。** 你这一侧可以更放手，但也别让 AI 直接合并 PR。

## 二、一次性准备（各自在自己机器上做一遍）

```bash
xcode-select --install      # 只需一次，装命令行工具，不需要完整 Xcode

git clone git@github.com:FelixAstra/menubar-keeper.git
cd menubar-keeper

make cert                   # 每台机器一次，见下方说明
make install                # 构建 → 装进 /Applications → 启动

make help                   # 忘了有什么命令就看这个
```

**`make cert` 为什么必须做。** 临时签名（ad-hoc）是绑定二进制哈希的，所以每次重新构建，macOS 都当成一个全新应用，会**重新索要辅助功能权限**。做一次本地自签名证书就永久解决。证书落在 `Scripts/signing/`，这个目录被 gitignore 了——证书是每个人自己的，不进仓库。

**必须从 `/Applications` 运行。** macOS 只认装在 `/Applications` 里的状态栏应用。从别处运行，它会把自己的图标也一起藏掉，**而且没有恢复的入口**。`make install` 会替你放到正确位置。

**她的 GitHub 认证。** 若 `git clone` 报权限错误，说明她的 SSH key 还没加到 GitHub 账号，或改用 HTTPS + Personal Access Token。这一步和仓库无关，一次配好即可。

## 三、日常循环：五步

每个改动都走这五步，不要跳步。

### 第 1 步：认领一件事

在 GitHub 上有一个对应的 Issue，把自己 **assign** 上去（Issues 右侧的 Assignees）。没有 Issue 就先建一个——**先有 Issue，再有分支**，这样对方随时知道你在动什么，避免两个人同时改同一块。

一件事 = 一个 Issue = 一个分支 = 一个 PR。中途发现还想顺手改点别的？**另开一个 Issue 和分支**，别混进当前 PR。

### 第 2 步：同步 `main`，开分支

```bash
git switch main
git pull
git switch -c feat/launch-at-login
```

分支名跟着改动类型走，和提交前缀一致：`feat/`、`fix/`、`docs/`、`ci/`。

**每次开分支前一定先 `git pull`。** 这是避免冲突最有效的一步，成本只有一秒钟。

### 第 3 步：改代码

各自用自己的 AI 助手。**改之前让它先读 `CONTRIBUTING.md` 和 `docs/ROADMAP.md`**，理由见第五节。

编辑循环就是：

```bash
make install        # 完整重建约 15 秒，没有增量构建，这是刻意的
```

### 第 4 步：本地自检（不能省）

CI 会替你跑同样的检查，但**等到 CI 红了再改是被动的**——尤其 warning 那条规则，本地不查就一定会踩。

```bash
./Scripts/build.sh          # 必须零 error、零 warning
```

如果你改的行为有探针对应（见 [CONTRIBUTING.md](../CONTRIBUTING.md) 的探测清单）：

```bash
touch /tmp/menubarkeeper-rowstatecheck    # 换成对应的探针名
make install
cat /tmp/menubarkeeper-debug.log
rm -f /tmp/menubarkeeper-*
```

**一次只能跑一个探针**——它们都要占用菜单栏，两个一起跑会互相干扰，被跳过的那个会在日志里明说。**这段日志要贴进 PR**，它是这个仓库目前最接近"测试结果"的东西。

### 第 5 步：推送分支、开 PR

```bash
git push -u origin feat/launch-at-login
```

推送后 GitHub 会给出创建 PR 的链接，点进去填写（有 PR 模板会引导你）。

**注意：`git push` 到自己的分支完全没问题，推 `main` 会被拒绝。** 这是设计如此。

### 然后：等 CI → 对方 review → 合并

- CI 的 **`Build`** 任务变绿（黄点是在跑，红叉是挂了，点进去看日志）
- 对方在 PR 里提意见，你推新提交即可，PR 会自动更新
- 合并用 **Squash merge**（把 PR 压成一个提交），保持 `main` 的历史一条线一件事
- 合并后分支会自动删除

**关于 review 的分工**：保护规则里 approve 数设的是 **0**，所以没有强制审批，谁都可以直接合并一个 CI 已通过的 PR。但这不等于不用看——**约定是：不合并自己开的 PR，让对方扫一眼再合**。CI 只检查"能不能编译"，检查不了"这个改动该不该做"。

## 四、提交信息怎么写

仓库历史用固定风格，AI 生成的提交信息通常不符合，**要手改**：

```
feat: make the menu bar mark a choice, and default it to the capsule
fix: stop the window's footer overlapping in English
docs(demo): say what the render actually costs
```

规则：conventional 前缀 + **小写** + **祈使句** + **结尾不加句号**。括号里是可选的 scope，只在改动局限在某一区域时用。

**标题说"改了什么"，正文说"为什么"。** 这个仓库的价值大半在推理里——一个解释了取舍的正文，比一个复述 diff 的正文有用得多。

## 五、用 AI 写代码的四条纪律

这一节是两人协作最容易出事的地方，请都读完。

### 1. 先让 AI 读 `docs/ROADMAP.md` 的"不可能"清单

那份文档里有一节列的是**"做不到"而不是"还没做"**——比如按应用单独设置粒度、已隐藏应用自己的菜单、Mac App Store 相关。这些都是逆向出来的硬边界，不是投入多少精力的问题。

**让 AI 在动手前先读它**，否则很容易写出一堆最终必须丢弃的代码。

### 2. 明确禁止 AI 碰这两个文件

- **`VERSION`** —— 只在发版提交里改。release 工作流会检查 tag 和这个文件是否一致，**而检查发生在 tag 推上去之后**，本地永远看不到报错。特性分支改它，会以"没人发现"的方式破坏下一次发版。
- **`CHANGELOG.md`** —— 版本段落是发版时写的，不要往已有段落里加条目。**你的改动写在 PR 描述里就行。**

AI 助手非常喜欢"顺手帮你更新版本号和变更日志"——**这是最典型的帮倒忙**。开分支时就明确告诉它这两个文件不许动。

### 3. 改用户可见文案，两个语言表都要补

- `Resources/en.lproj/Localizable.strings`
- `Resources/zh-Hans.lproj/Localizable.strings`

**缺 key 会原样渲染出 key**（比如屏幕上出现 `row.state.hidden`），这是刻意设计，专门用来暴露遗漏。

**两种语言各写各的句子，不要互相翻译。** 这个项目两种语言地位平等，直译出来的英文或中文一眼就能看出来。

### 4. "AI 说改好了"不算完成

必须自己跑一遍第四节的自检。AI 经常：
- 说改了但没实际写入文件
- 引入未使用的变量（**一个 warning 就让 CI 挂**）
- 声称"已测试"但根本没运行过

## 六、热点文件：谁改谁先说

这个仓库有两处**任何人都会碰到的文件**，是冲突的主要来源：

| 文件 | 为什么容易撞 |
|---|---|
| `Resources/*.lproj/Localizable.strings` | 只要改动涉及界面文字，两个人都要在这里加条目 |
| `Sources/Support/Localization.swift` | 新增 key 要在这里注册 |
| `Sources/Support/Diagnostics.swift` | 新增或修改探针都在这个文件里 |

**约定**：动这三个文件（以及任何你想同时改的其他公共文件）之前，在 Issue 里回一句"我要动 lproj / Localization"。对方的改动如果已经合了，你先 `git switch main && git pull` 再继续，冲突量会小很多。

真撞上了也不可怕：Git 对这种"两边各加了几行"的冲突处理得很好，把两边的条目都保留即可。**冲突时绝对不要 `git push --force`**——分支保护也禁止强推。

## 七、PR 自检清单

开 PR 前对着过一遍：

- [ ] 一个 PR 只做一件事，能一口气读完
- [ ] CI 的 `Build` 变绿
- [ ] 没有改 `VERSION`、没有改 `CHANGELOG.md` 的已有段落
- [ ] 改了文案 → 两个语言的 `.strings` 都补了
- [ ] 改了探针覆盖的行为 → 跑过探针，日志贴进 PR
- [ ] 改了 README 里的图片 → 对应的 `?v=N` 已 +1（**漏改的话所有人继续看旧图，而且不报错**；每张图有各自的编号，只动你改的那张）
- [ ] 没有提交 `build/`、`*.dmg`、`Scripts/signing/`、`node_modules`（`.gitignore` 已覆盖）

## 八、出问题怎么办

**CI 红了。** 点进 Actions 看是哪个 step。警告检查和编译失败会分别报出。在本地跑 `./Scripts/build.sh` 通常能复现。

**我的分支落后 `main` 了。** 网页 PR 页面如果有 **Update branch** 按钮，点它最省事。命令行则：

```bash
git switch main && git pull
git switch feat/launch-at-login
git merge main          # 或 git rebase main，二选一，别混用
git push
```

**她说推 `main` 被拒绝。** 这是分支保护在正常工作，不是权限坏了。让她改推自己的分支然后开 PR。

**PR 开错分支 / 开多了。** 直接关闭 PR，删掉分支，重开一个。没有任何副作用，不要为了"不浪费"而硬着头皮合。

**拿不准一件事该不该做。** 开 Issue 问，别先写代码。这个项目的 ROADMAP 列了不少"看起来该做但其实做不到"的事。

## 九、命令速查

```bash
# 环境
make help                       # 列出所有可用目标
make cert                       # 每台机器一次：创建本地签名证书
make install                    # 构建 → 装进 /Applications → 启动
make native                     # 只为本机构建，更快
make build                      # 构建通用二进制（arm64 + x86_64）
make verify                     # 检查已安装应用的签名
make clean                      # 删除 build/

# 直接调用脚本
./Scripts/build.sh              # CI 用的就是这条
./Scripts/package-dmg.sh        # 打 DMG

# 探针
touch /tmp/menubarkeeper-<探针名>
make install
cat /tmp/menubarkeeper-debug.log
rm -f /tmp/menubarkeeper-*

# 日常协作
git switch main && git pull
git switch -c feat/<改动名>
git push -u origin feat/<改动名>
```

## 十、这个仓库的底线（不可协商）

两条，摘自 [CONTRIBUTING.md](../CONTRIBUTING.md)，因为 AI 助手最容易在这上面越界：

1. **不加第三方依赖，不引入 Xcode 工程。** 连应用图标都是用 Core Graphics 画的（`make icon`），而不是依赖图片库——这就是全项目的标准。真觉得某个依赖不可避免，**先开 Issue 讨论，别先写代码**。
2. **私有框架属于逆向研究，不是稳定 API。** 应用驱动 `MenuBarClientCore` 并读取系统辅助功能树，两者都不稳定，在一个 macOS 版本上验证过的行为，换一个版本就不算验证过。改这块必须**在真实菜单栏上重新验证**——探针就是干这个用的。

---

有疑问时，回到第一句话：**一人一个分支，一个分支一件事，一切都经 PR 进 `main`。**
