# 1.1.0 發版準備計畫

日期：2026-10-22。依據：[規格](RELEASE_1.1.0_SPEC.md)。

## Git 收尾計畫（2026-10-30）

- 先審查 `HEAD` 相對工作目錄的候選版變更，以及 `origin/main...HEAD` 的詞彙快捷學習，核對規格與隱私、取消及儲存邊界。
- 執行 `git diff --check`、plist／HTML／本機連結與版本一致性檢查，重跑 `scripts/test-vocabulary.sh`。不啟動正式資料宿主，不重裝 App。
- 更新本計畫與交接的收尾證據，只提交已確認的 9 個檔案，保留 AI 署名與 `Human-Review: 僅下指令`。
- 推送 `feat/vocabulary-quick-learning`，確認遠端 `main` 沒有新增提交後以 fast-forward 合併，推送 `main` 並核對遠端 SHA。否決不必要的 merge commit，因為目前分支是 `main` 的直接後代；若分支分歧則先重新審查差異。
- 狀態：審查與驗證完成，規範與規格兩軸皆未發現阻擋 Git 合併的問題。Git 提交、推送與合併結果由本輪提交歷史及遠端 SHA 核對記錄；以下 2026-10-22 紀錄保留為歷史證據，不代表本輪即時安裝狀態。

### 本輪驗證結果

- `git diff --check`、`plutil -lint VoiceInk.xcodeproj/project.pbxproj`、`xmllint --html --noout release-notes/1.1.0.html` 通過；28 個本機文件連結、8 組版本／build 欄位、23 個新增繁中字串檢查通過。公開 feed 與 1.0.1 更新說明未變更。
- `./scripts/test-vocabulary.sh` exit code 0，未簽署 `build-for-testing`、合成舊資料遷移及 35 項隔離測試（2 suites）通過。日誌與測試產物：`/tmp/wagong-vocabulary.aZIZnQ/`。沿用 `-skipPackagePluginValidation -skipMacroValidation`，不啟動 App 宿主。
- 未重跑完整宿主、真實 Provider、硬體、跨 App、VoiceOver、簽章或公證驗證；沒有重新安裝或發布 App。這些限制不因 Git 合併而解除。

## 階段一：基準與規格

- 已即時查證 GitHub 最新公開 Release 為 v1.0.1，公開 tag 指向 344d727，公開 App build number 為 2。
- 本輪起點為功能分支 feat/vocabulary-quick-learning、a6a2310，工作區乾淨。遠端 main 仍為 576939b，不含最後一筆詞彙快捷學習。
- spec 與此計畫依序先寫入，實作後回填相同 checklist。
- 狀態：完成。

## 階段二：版本與文件

- 修改 VoiceInk.xcodeproj/project.pbxproj 中現有 8 組版本與 build number，保持 Swift flags、Bundle ID、簽署與依賴不變。
- 修改 README.md、CHANGELOG.md、BUILDING.md、handoff.md，新增 release-notes/1.1.0.html。
- 不修改舊 release-notes 與 appcast.xml，不新增 GitHub 資產連結。
- 風險：把尚未發布誤寫成已發布，或將已知故障寫成修正；依 spec、目前 Issue 與來源提交逐項對照。
- 狀態：完成，8 組既有版本欄位已同步，4 份既有文件與候選更新說明已更新。

## 階段三：檢查與建置

- 執行 git diff --check、plutil、HTML 與文件連結檢查、版本欄位檢查。
- 執行 scripts/test-vocabulary.sh，使用實際 App library 的隔離測試，不啟動與正式 App 共用資料的測試宿主。
- 先前同功能來源的完整宿主測試為 253 項、251 通過、0 失敗、2 略過；本次僅版本／文件改動，不將舊報告冒充本次重跑。
- 一般 Release 用既有 Developer ID 流程重建，沿用鎖定套件及原 entitlement，不清空 Swift compilation conditions。
- 狀態：完成，靜態檢查、35 項隔離測試及一般 Release 建置通過。

## 階段四：候選版安裝與交接

- 先備份目前正式 App，驗證備份簽章與拋棄式副本交換／復原。
- 只在候選驗證通過後關閉共用 Bundle ID App，替換 /Applications/Wa-Gong.app。
- 核對實際產物版本 1.1.0、build 3、Build ID、source fingerprint／dirty 狀態、helper manifest、主 App／helper 簽章與唯一執行程序。
- 本機收據保留於 .local-build，不納入 Git；handoff 記錄必要來源與未驗收清單，不保存憑證或私人資料。
- 狀態：完成，1.1.0 已安裝並啟動於正式位置，來源／版號／簽章／權限／helper 及唯一程序已核對；公開發版與實機驗收仍未完成。

## 公開發版前阻擋

- 詞彙 AX 選取、修正表單、取消、跨 App 交付與 VoiceOver 待實機驗收。
- Majestouch USB 右 Control、休眠喚醒與本機模型效能／品質仍待實機驗收。
- 確定最終提交與合併範圍後，再取得推送 main、Tag、公證及 GitHub Release 的明確授權，建立對應來源／DMG／Sparkle 簽章與發布證據。
- 公開發布時須重新核對更新說明日期與候選標示，確認實際上傳的來源及產物後才將「尚未發布」改成公開版本；本輪不提前填入發布日期或下載網址。

## 驗證紀錄

- `git diff --check`、`plutil -lint VoiceInk.xcodeproj/project.pbxproj`、`xmllint --html --noout release-notes/1.1.0.html` 通過。所有新增／修改 Markdown 的本機連結存在，現有 8 組版本為 1.1.0、build number 為 3；appcast.xml 與既有 release-notes 未修改。
- `./scripts/test-vocabulary.sh` 通過，日誌 `/tmp/wagong-1.1.0-vocabulary-validation.log`，產物 `/tmp/wagong-vocabulary.JcUjWf/`，結果為 35 項、2 suites 通過，0 失敗。使用未簽署 Debug build-for-testing、`-skipPackagePluginValidation -skipMacroValidation`，連結 App library 做隔離測試，包含合成舊資料遷移，不啟動正式資料宿主。
- 一般 Release 日誌 `/tmp/wagong-1.1.0-release-build.log` 為 `BUILD SUCCEEDED`，未使用 LOCAL_BUILD，沿用原 Developer ID 與 Team。主 App 與 XPC 產物分別讀回版本 1.1.0、build number 3。
- 正式 App：`/Applications/Wa-Gong.app`；Build ID `LOCAL-20261021T180412Z-a6a2310`；來源 base SHA `a6a23103179ec3104feb248f2e9b2625a4d5469a`，source state 為 dirty，指紋 `fc7d34d2d85a45be14c8a6fdb76f5ca6e439fe7d24e068b1bbd0448059e284fc`。新版本欄位尚未提交，不把 base SHA 冒充完整候選提交。
- 安裝收據 `.local-build/release-1.1.0-20261022/metadata.json`。先完成備份，再於拋棄式副本驗證交換與復原；主 App／helper strict 簽章、manifest 雜湊、既有完整 entitlements 一致性與唯一正式位置程序通過。未執行實際回滾，兩份前版備份保留。
- 本輪不涉及功能邏輯修改，未重跑完整宿主測試，亦未做真實錄音、雲端請求、跨 App 或 VoiceOver。既有 253 項宿主報告只作歷史參考，不算本輪結果。
- 變更仍在功能分支未提交，未推送、merge、Tag、公證、建立 GitHub Release 或修改公開更新 feed。

## 雲端整理觀察暫停追蹤（2026-10-22）

- 使用者明確要求 Gemini 與 Claude 兩項先不追蹤，移出本輪修復待辦與發版阻擋。Gemini 外部伺服器短暫異常尚未查證；Claude 後續正常為使用者回報，不是修復證據。
- 文件調整計畫：先更新本 spec 與計畫，再同步本機 Issue、README、CHANGELOG、候選更新說明與最新交接；保留較早歷史紀錄，不修改 App、設定或模型，不發出測試請求。
- 本機 Issue 的舊修復建議改為封存參考，不持續監控或自動重啟；只有使用者再次回報或明確要求時才重新評估。
- 驗證方式為文件狀態、連結、HTML 與 diff 檢查，不重跑建置或替換 App。其他實機與無障礙待驗項目維持原狀。
