# MyAnimeList API 申请

PaperVN 接入 MAL 分两步：先注册 App 拿到 Client ID（马上就能用来开发和测试），再申请商业使用的书面授权（上线付费功能之前必须拿到）。

> 以下表单字段是按 MAL API 配置页的常见写法整理的，页面改版后名字可能不同，以实际页面为准。

## 一、注册 App，拿到 Client ID

1. 用你的 MAL 账号登录 https://myanimelist.net ，打开 https://myanimelist.net/apiconfig ，点 **Create ID**。
2. 按下面填写：

| 字段 | 填写 |
|---|---|
| App Name | PaperVN |
| App Type | **iOS**（没有 client secret，App 用 PKCE 登录，不会泄露） |
| App Description | 见下方英文描述 |
| App Redirect URL | `papervn://oauth/mal`（必须和 App 里完全一致） |
| Homepage URL | https://papervn.jizpaper.com |
| Commercial / Non-Commercial | **Commercial**（PaperVN 有订阅，照实选） |
| Name / Company Name | 你的开发者名称（与 App Store 上一致） |
| Purpose of Use | 选最接近“应用 / 第三方客户端”的选项 |

App Description 可以填：

> PaperVN is an iOS app for tracking visual novels, anime, manga and light novels. Users sign in with their own MyAnimeList account (OAuth 2.0 PKCE) to import and update their anime and manga lists. PaperVN is not affiliated with MyAnimeList.

3. 勾选同意 API License and Developer Agreement，提交后得到 **Client ID**。
4. 把 Client ID 写进 `Config/PaperVN.private.xcconfig`（这个文件不进仓库）：

   ```
   MAL_CLIENT_ID = 你的ClientID
   ```

5. 重新编译，在「账户 › MyAnimeList」登录测试。登录后 PaperVN Sync 会导入你的动画、漫画与轻小说列表，在资料库里改状态或进度会写回 MAL。

## 二、申请商业使用的书面授权

协议第 3(a)(xiv) 条要求：商业 App（订阅、付费下载、广告等）未经书面授权不得通过 MAL 内容获得收入。第 3(c) 条还限制在服务器上存储含个人信息的 MAL 内容，这和 PaperVN Sync 的多设备同步（把资料库存到服务器）直接相关，申请时一起问清楚。

1. 通过 MAL 帮助中心提交请求：https://help.myanimelist.net → 右上角 **Submit a request**，类型选与 API / Business 相关的选项。客服不回答技术问题，但商业授权属于业务问题。
2. 用下面的邮件模板，附上截图（资料库、MAL 登录页、同步任务页）。
3. 保存往来记录。拿到书面授权之前：
   - 付费功能不要依赖 MAL 数据（作品数据优先用 AniList、Bangumi）；
   - 服务器上的多设备同步不要保存来自 MAL 的列表数据。

## 三、申请邮件模板

Subject: **Commercial use request for MyAnimeList API – PaperVN (iOS)**

```
Hello MyAnimeList team,

I am the developer of PaperVN, an iOS app for tracking visual novels, anime, manga and
light novels (App Store: https://apps.apple.com/us/app/papervn/id6793787678,
website: https://papervn.jizpaper.com).
I registered the app on the API configuration page with Client ID <your Client ID>,
marked as commercial, and I would like to request written authorization for commercial
use under section 3(a)(xiv) of the API License and Developer Agreement.

How PaperVN uses the MyAnimeList API
- Users sign in with their own MyAnimeList account via OAuth 2.0 (PKCE). We never ask
  for or store passwords.
- PaperVN imports the user's own anime and manga lists and writes back changes the user
  makes in the app (status, score, progress) through the official v2 endpoints.
- Title, cover image, mean score and episode/chapter counts are shown only alongside the
  user's own list entries, with attribution to MyAnimeList and a link to the
  corresponding MyAnimeList page.
- We do not scrape the website, do not bulk-download the database, and do not use
  MyAnimeList data to train models.
- Access tokens are stored only in the iOS Keychain on the user's device.

The MyAnimeList integration is not included in the current App Store version. It is
ready in development, and we will roll it out gradually only after receiving your approval.

Business model: delayed-free
- PaperVN follows a "delayed-free" model: new features are first available to
  subscribers, then become free for everyone in later updates. It is not a permanent
  paywall.
- PaperVN is free to download, and syncing with MyAnimeList is always free.
- An optional subscription ("PaperVN Enshi") gives early access to the new anime, manga
  and light novel tracking features. These features will be opened to all users step by
  step through App Store updates, and all of them will be free by December 1, 2030.
- Existing features of the app are never moved behind the subscription.
- The full source code of the app, including the subscription features, is open source
  on GitHub (https://github.com/JiZPaper/PaperVN), licensed under CC BY-SA 4.0.
- The app shows no advertising.

Questions
1. May PaperVN offer the subscription described above while using the MyAnimeList API?
   If there are conditions (attribution, revenue limits, fees), please let me know.
2. PaperVN offers optional multi-device sync. May we store a user's own list entries
   (status, score, progress) on our server, only at that user's request and only for
   syncing their own devices? If not, we will keep MyAnimeList data on the device only.

PaperVN is not affiliated with or endorsed by MyAnimeList, and we will state this in the
app. I'm happy to provide test builds, screenshots or any further details.

Thank you for your time.

Best regards,
<Your name>
<Developer / company name>
<Contact email>
```
