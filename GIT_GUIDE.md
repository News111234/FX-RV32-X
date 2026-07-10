# Git 推送指南 —— 如何更新 GitHub

每次修改代码后，只需在终端里依次敲三行命令。

## 第一步：打开终端

在项目文件夹 `D:\Path\RISC-V-TEST\Project\FX-RV32_Custom` 的地址栏输入 `bash` 然后回车：

```
D:\Path\RISC-V-TEST\Project\FX-RV32_Custom  →  输入 bash → 回车
```

会弹出一个命令行窗口。

## 第二步：三行命令

```bash
git add -A
git commit -m "这里写你改了什么"
git push origin master
```

一行一行输，每行输完按回车。

## 示例

比如你今天改了 `alu.v`，修了一个 bug：

```bash
git add -A
git commit -m "修复 ALU 加法溢出 bug"
git push origin master
```

执行完就推送到 GitHub 了，去 https://github.com/News111234/FX-RV32-X 就能看到更新。

## 每条命令拆解

### 第一条：`git add -A`

```
git  add  -A
│     │    │
│     │    └── -A = --all 的缩写，意思是"所有文件"
│     │         包括：新增的、修改过的、删除的，全部加入暂存区
│     │
│     └── add：把文件的改动加入"暂存区"（staging area）
│         暂存区就是一个"待提交清单"——你告诉 git：下次 commit 时，这些文件我要了
│
└── git：调用 git 这个程序
```

**`-A` 的几个替代写法：**
| 写法 | 含义 | 什么时候用 |
|------|------|------------|
| `git add -A` | 整个仓库所有改动 | 改了一堆文件，全都要提交 |
| `git add .` | 当前目录及子目录的改动 | 同上，效果差不多 |
| `git add 文件路径` | 只加那一个文件 | 只改了一个文件，或者只想提交某一个 |
| `git add 文件1 文件2 文件3` | 只加指定的几个文件 | 改了三个文件，但有五个不想提交 |

**只添加单个文件的例子：**

```bash
# 只改了 alu.v，其他文件不想提交
git add core/exu/alu.v
git commit -m "修复 ALU 加法溢出 bug"
git push origin master

# 改了三个文件，只想提交其中两个
git add core/exu/alu.v core/id/decoder.v
git commit -m "修复 ALU 和译码器 bug"
git push origin master
```

文件路径不用手打——输入 `git add core/` 然后按 `Tab` 键会自动补全。

---

### 第二条：`git commit -m "说明文字"`

```
git  commit  -m  "修复 ALU 加法溢出 bug"
│     │       │        │
│     │       │        └── 你写的提交说明，必须用引号包起来
│     │       │             写清楚这次改了什么，以后翻历史一眼就懂
│     │       │
│     │       └── -m = --message 的缩写
│     │           意思是"后面跟的是提交说明"
│     │           如果不写 -m，git 会弹出一个编辑器让你写说明（很烦，不推荐）
│     │
│     └── commit：把暂存区里的所有改动打包成一个"快照"（snapshot / commit）
│          每个 commit 有唯一的 ID（一串哈希值，比如 af9b4ba）
│          将来可以随时回到任意一个 commit 的状态
│
└── git
```

**为什么要写说明？** 不然三个月后你看到一堆 `update`、`fix`、`111` 的提交记录，完全不知道哪个是哪个。

---

### 第三条：`git push origin master`

```
git  push  origin  master
│     │      │       │
│     │      │       └── master：推送到远程的 master 分支
│     │      │            分支 = 一条独立的开发线，master 是默认主分支
│     │      │            你暂时不需要关心其他分支
│     │      │
│     │      └── origin：远程仓库的别名
│     │           git remote add origin git@github.com:News111234/FX-RV32-X.git
│     │           当时这条命令把 GitHub 地址记成了 "origin" 这个名字
│     │           你可以用 git remote -v 查看所有远程地址
│     │
│     └── push：把本地的 commit 记录推送到远程仓库
│          注意：push 推送的是 commit，不是文件
│          所以必须先 add → commit，才能 push
│
└── git
```

**所以完整流程是：**

```
你改文件 → add(放进清单) → commit(打包存档) → push(上传到 GitHub)
```

三步缺一不可，顺序不能乱。

## 删除文件

普通删文件（在文件夹里右键删除）git 是不会自动感知的。需要用 git 命令来删：

```bash
git rm 文件路径                     # 删一个文件
git rm 文件1 文件2                  # 删多个文件
git rm -r 文件夹名                  # 删整个文件夹（-r = recursive，递归）
```

**完整流程（和 add 一样，只是把 add 换成 rm）：**

```bash
git rm core/exu/old_alu.v          # 告诉 git：删掉这个文件
git commit -m "删除废弃的旧 ALU"     # 存档
git push origin master              # 上传
```

**注意：** `git rm` 会同时删掉本地文件和 git 记录。如果你只是想"别再跟踪这个文件了，但本地保留"，加 `--cached`：

```bash
git rm --cached 文件路径            # 从 git 里移除，但本地文件还在
```

这个一般用不到，除非你不小心把不该传的文件 add 进去了。

---

## 常见问题

**Q: 我改了文件，但 git 说不认识？**

先确认终端当前目录对不对：
```bash
pwd
```
应该显示 `/d/Path/RISC-V-TEST/Project/FX-RV32-Custom`。如果不是，先 `cd` 过去。

**Q: 推送时报错 "rejected"？**

可能是 GitHub 上有别人（或另一台电脑）推了东西。执行：
```bash
git pull origin master --no-rebase
git push origin master
```

**Q: .gitignore 是干什么的？**

它告诉 git "这些文件不要上传"。比如论文 .tex、Vivado 编译产物、个人笔记等，都会被自动忽略。你在文件夹里放什么都没关系，只要匹配 `.gitignore` 里的规则就不会被推上去。

**Q: 我怎么知道哪些文件会被推送？**

```bash
git status
```
会列出所有改动。绿色的是会推送的，不会被 `.gitignore` 拦住的。
