# 本次收尾與候選提交範圍（2026-10-21）

## 最後交接：正式位置替換與模型清理

本節依本機收據記錄 2026-10-21 已執行的結果；以下各節保留分批提交時的歷史狀態。「未重裝／未 push」等舊敘述不代表本節之後的狀態。

### 安裝與驗證範圍

- 正式位置：`/Applications/Wa-Gong.app`，版本 1.0.1，Build ID `LOCAL-20261020T183055Z-0eb0cd9`。
- 原始碼：`0eb0cd9327884b68bfc271cb8facab06eb76c30c`，來源指紋 `ad32efa0472264fd23c81462d2be2d9947e8940c9b85d995c6de51f9bf47c673`。後續文件提交不改變 App 程式碼。
- 選用正常 Release，未使用 `LOCAL_BUILD`；既有 Developer ID 與 Team `8N33V8XXTX`、Bundle ID `com.jackie-yeh.wagong` 保持不變。簽章不附時間戳，未提交公證，不宣稱可公開發布。
- 最終收據查證時間 `2026-10-21T02:41:59+08:00`：僅正式 App 執行，測試 App 關閉。主 App 的 `codesign --verify --deep --strict` 通過；helper manifest／Team 通過，最終 entitlements 與原正式版完全相同，包含 Production iCloud 與既有 Keychain 群組。這些檢查不代表雲端同步或真實 Provider 已驗收。
- 實際安裝的 helper 在網路拒絕 sandbox 與私有 pipe 中成功載入保留的 TEA，完成回收；此探針未錄音、未辨識、未呼叫雲端，雲端請求數為 0。
- 提交來源的測試版完整宿主測試為 243 項：241 通過、0 失敗、2 項既有略過。報告 `.local-build/Logs/Test/Test-VoiceInk-2026.10.21_02-19-08-+0800.xcresult`；日誌 `/tmp/wagong-committed-test-app-install-20261021.log`。正式 Release 建置另通過，日誌 `/tmp/wagong-production-build-20261021.log`。
- Release 首輪因建置指令錯誤清空 Swift compilation conditions，造成套件編譯失敗；移除該覆寫後成功，未修改套件或原始碼。失敗紀錄保留於 `/tmp/wagong-production-build-20261021-failed-flags.log`。

### 備份與保留決策

- 原正式 App 保留為 `/Applications/.Wa-Gong.previous-20261021.app`；獨立備份 `.local-build/production-replacement-20261021/backup/Wa-Gong.app`，原 Build ID `LOCAL-20261005T004831Z-2042dbc`。兩者 strict 簽章驗證通過。
- 已從備份建立還原副本，比對 executable SHA／Build ID 與驗證簽章；交換及反向復原流程在拋棄式 App 副本實測。正式 App 啟動成功，未執行實際回滾。測試用副本已移除，兩份真正備份仍保留。
- 保留正式 App 備份，否決為回收空間直接刪除，因為仍需提供可驗證的前版產物。
- 操作收據 `.local-build/production-replacement-20261021/metadata.json` 與 `model-cleanup-receipt.json` 保留本機，不進 Git；簽署設定與 profile 也不納入版控。

### 模型清理結果

本輪在正式 helper 載入保留模型成功後，依使用者授權移除以下兩檔。刪除前以已知開啟檔案驗證量測方法，再核對來源未被開啟。

| 移除檔案（相對專案） | bytes | 原因 |
| --- | ---: | --- |
| `tools/local-model-probe/.runtime/TEA-ASR-1.1-Q6_K.gguf` | 1,692,286,464 | 與 App 管理模型完整 SHA-256 相同的重複檔案 |
| `tools/local-model-probe/.runtime/Qwen3-ASR-0.6B-Q8_0.gguf` | 850,423,456 | 現有模式未引用，使用者已選擇本機 TEA 搭配雲端整理 |

合計 2,542,709,920 bytes，約 2.54 GB。保留 `~/Library/Application Support/com.jackie-yeh.wagong/TranscribeCpp/tea-asr-1.1-q6-k/TEA-ASR-1.1-Q6_K.gguf`，SHA-256 `2417fa52d49f852bfc11704190e10ddb681c343a661a3a3d1bb213876c780b68`。共用 FluidAudio Parakeet 快取約 461 MiB 保留，因為尚未確定其他 App 的使用情況；未刪除錄音、歷史、設定或金鑰。這輪不同於先前約 12.8 GiB 的 Ollama／舊 ASR 快取清理。

### 本次文件收尾與未結案

本次只修改 `handoff.md` 與本文件，再依「收尾」授權提交並推送 `origin` 的 `feat/local-tea-model-workflow`。不合併／推送 `main`，不建立 PR 或發布。本次未更動 App 原始碼，未重跑完整測試；以差異檢查及操作收據核對文件。

仍未結案：Gemini 逾時根因與錄音整理接線、Claude 額外說明放行、模型選單精簡，以及 Majestouch USB 右 Control／真實錄音／取消／休眠／VoiceOver／跨 App 交付與品質效能實機驗收。各項重啟條件見 `handoff.md` 及雲端整理 Issue，不把本次安裝或測試成功視為以上問題已解決。

## 分批提交前狀態

- 分支：`main`，HEAD `06a876d45730ea3373292bf191b498c8d4602e17`。
- 安裝與執行：`T-20261020-153150-124F8A70`，狀態 `CURRENT`、`Running: MATCH`。
- 最近完整測試：241 通過、0 失敗、2 項既有 Vocabulary 略過，本次未重跑。
- 本機文件整理已完成；未 commit、push、建立 PR、發布或停止使用者服務。

## 原始提交提案（後續已授權本機分批提交）

工作區含本次開始前已存在的雲端／Ollama 串接與鍵盤修改，部分與本輪模型工作共用檔案。依使用者收尾規則，這些既有變更不能自動併入。

建議核准後，將下列模型整合與文件候選範圍一併提交至新功能分支 `feat/local-tea-model-workflow`，另保留鍵盤、規則檔及測試產物。理由是較早模型功能與本輪 helper、測試及共用畫面相互依賴；只按檔名提交本輪新增檔，無法代表已測試的完整產物。否決直接 `git add .`、提交鍵盤修改或推送 main。

核准後仍需逐檔確認內容、秘密與模型二進位排除，以及從候選提交範圍獨立建置／測試；目前完整測試包含工作區既有鍵盤修改，不能當成排除該修改後的測試證據。若檢查顯示額外依賴，先回報，不偷加範圍。

commit 必須包含 `Co-Authored-By:` 與 `Human-Review: 僅下指令`，除非人類另明示實際審閱程度。本文件不是對外 PR 文案。

## 已交付與仍未解決

- 已交付：App 管理本機 TEA、模型來源與授權標示、Refine 原名修正、中文／已安裝／全部模型篩選、授權移除約 12.8 GiB 舊模型。
- 未解決：模型清單仍雜亂，需先確認使用者指的是模型頁或模式下拉，再核准更精簡的畫面。
- 未解決：Gemini 整理約 20 秒逾時，根因未確認；錄音整理尚未接入統一單次請求路徑。
- 未解決：Claude 額外說明被當成整理正文放行，後續單句正常不等於修好。
- 未驗收：完整品質集、實際 UI／VoiceOver、取消與跨 App 交付、休眠喚醒及發布。
- 問題證據與重啟條件見 `handoff.md`、`docs/issues/雲端文字整理逾時與輸出污染.md`。

## 已確認的模型提交範圍，包含較早模型工作

- `docs/SESSION_CLOSEOUT_2026-10-21.md`
- `Shared/TEAWorkerProtocol.swift`
- `TEAWorker/main.swift`
- `VoiceInk.xcodeproj/project.pbxproj`
- `VoiceInk/Localizable.xcstrings`
- `VoiceInk/Models/LocalSpeechModelFilter.swift`
- `VoiceInk/Models/PromptTemplates.swift`
- `VoiceInk/Models/TranscriptionModel.swift`
- `VoiceInk/Models/TranscriptionModelRegistry.swift`
- `VoiceInk/Modes/ModeConfigFormView.swift`
- `VoiceInk/Modes/ModeViewComponents.swift`
- `VoiceInk/Resources/TEA-ASR-LICENSE.txt`
- `VoiceInk/Resources/TEA-ASR-NOTICE.md`
- `VoiceInk/Resources/TEA-Qwen-Apache-2.0.txt`
- `VoiceInk/Resources/asr-connection-test.wav`
- `VoiceInk/Services/AIEnhancement/AIChatCompletionService.swift`
- `VoiceInk/Services/AIEnhancement/AIEnhancementService.swift`
- `VoiceInk/Services/AIEnhancement/AIService.swift`
- `VoiceInk/Services/AIEnhancement/EnhancementRequestRetry.swift`
- `VoiceInk/Services/AIEnhancement/LocalCleanupOutputPolicy.swift`
- `VoiceInk/Services/AIEnhancement/NativeRefinementClient.swift`
- `VoiceInk/Services/AIEnhancement/OllamaRefinementClient.swift`
- `VoiceInk/Services/AIEnhancement/ReasoningConfig.swift`
- `VoiceInk/Services/AIEnhancement/VoiceInkRefineService.swift`
- `VoiceInk/Services/AIEnhancement/VoiceInkRefineXPCClient.swift`
- `VoiceInk/Services/OllamaService.swift`
- `VoiceInk/Services/SingleRequestHTTPTransport.swift`
- `VoiceInk/Transcription/Cloud/CustomModelConnectionTester.swift`
- `VoiceInk/Transcription/Cloud/OpenAICompatibleTranscriptionService.swift`
- `VoiceInk/Transcription/Engine/TranscriptionPipeline.swift`
- `VoiceInk/Transcription/Engine/TranscriptionSession.swift`
- `VoiceInk/Transcription/TranscribeCpp/TEAModelInstaller.swift`
- `VoiceInk/Transcription/TranscribeCpp/TEARuntimeActivity.swift`
- `VoiceInk/Transcription/TranscribeCpp/TEARuntimeManager.swift`
- `VoiceInk/Transcription/TranscribeCpp/TEATranscriptDecoder.swift`
- `VoiceInk/Transcription/TranscribeCpp/TEATranscriptionService.swift`
- `VoiceInk/Transcription/TranscribeCpp/TranscribeCppModelCatalog.swift`
- `VoiceInk/Transcription/TranscribeCpp/TranscribeCppModelManager.swift`
- `VoiceInk/Transcription/TranscribeCpp/TranscribeCppTranscriptionService.swift`
- `VoiceInk/Views/AI Models/CustomProviderManagementView.swift`
- `VoiceInk/Views/AI Models/ModelManagementView.swift`
- `VoiceInk/Views/AI Models/TranscribeCppModelCardView.swift`
- `VoiceInk/Views/AudioPlayerView.swift`
- `VoiceInk/Views/Dictionary/VocabularyView.swift`
- `VoiceInk/Views/Recorder/AudioVisualizerView.swift`
- `VoiceInkRefineXPC/VoiceInkRefineInferenceEngine.swift`
- `VoiceInkRefineXPC/VoiceInkRefineXPCService.swift`
- `VoiceInkTests/CustomASRContractTests.swift`
- `VoiceInkTests/LocalModelContractTests.swift`
- `VoiceInkTests/LocalSpeechModelFilterTests.swift`
- `VoiceInkTests/NativeRefinementClientTests.swift`
- `VoiceInkTests/TEAWorkerContractTests.swift`
- `VoiceInkTests/TaiwanASRRefinementTests.swift`
- `VoiceInkTests/VoiceInkTests.swift`
- `docs/BREEZE_TEA_INTEGRATION_PLAN.md`
- `docs/LOCAL_ASR_OLLAMA_INTEGRATION_PLAN.md`
- `docs/LOCAL_MODEL_CATALOG_FILTER.md`
- `docs/TEA_APP_MANAGED_RUNTIME_SPEC.md`
- `docs/issues/第三方模型來源標示錯誤.md`
- `docs/issues/雲端文字整理逾時與輸出污染.md`
- `handoff.md`
- `scripts/test-app.sh`
- `tools/local-model-probe/.gitignore`
- `tools/local-model-probe/GGUFProbe.swift`
- `tools/local-model-probe/GGUFWorker.swift`
- `tools/local-model-probe/LocalFixAcceptance.swift`
- `tools/local-model-probe/ManagedTEAAcceptance.swift`
- `tools/local-model-probe/ManagedTEASignedAcceptance.swift`
- `tools/local-model-probe/README.md`
- `tools/local-model-probe/analyze_results.py`
- `tools/local-model-probe/artifacts.json`
- `tools/local-model-probe/build_probe.py`
- `tools/local-model-probe/download.py`
- `tools/local-model-probe/fixtures.py`
- `tools/local-model-probe/gguf_server.py`
- `tools/local-model-probe/loopback-only.sb`
- `tools/local-model-probe/ollama-model.json`
- `tools/local-model-probe/prepare_ollama.py`
- `tools/local-model-probe/run_native.py`
- `tools/local-model-probe/run_ollama.py`
- `tools/local-model-probe/serve_ollama.py`
- `tools/local-model-probe/test_contracts.py`
- `tools/local-model-probe/verify_app_asr.py`
- `tools/local-model-probe/verify_app_ollama.py`
- `tools/local-model-probe/verify_combined.py`
- `tools/local-model-probe/verify_gguf_service.py`
- `tools/local-model-probe/verify_managed_tea.py`
- `tools/taiwan-asr/.gitignore`
- `tools/taiwan-asr/README.md`
- `tools/taiwan-asr/models.json`
- `tools/taiwan-asr/probe.py`
- `tools/taiwan-asr/requirements.lock`
- `tools/taiwan-asr/server.py`
- `tools/taiwan-asr/test_probe.py`
- `tools/taiwan-asr/test_server.py`
- `tools/taiwan-asr/verify_refinement.swift`
- `tools/taiwan-asr/verify_service.py`
- `tools/taiwan-asr/verify_transport.swift`

## 模型提交階段先行排除的項目（後續處理見文末）

- `AGENTS.md`
- `CLAUDE.md`
- `VoiceInk/Services/KeyboardDiagnosticsSnapshot.swift`
- `VoiceInk/Services/SystemInfoService.swift`
- `VoiceInk/Shortcuts/KeyboardEventAttributionBroker.swift`
- `VoiceInk/Shortcuts/RecordingShortcutManager.swift`
- `VoiceInk/Shortcuts/ShortcutMonitor.swift`
- `VoiceInkTests/KeyboardDiagnosticsSnapshotTests.swift`
- `VoiceInkTests/ShortcutMonitorDeviceRoutingTests.swift`
- `default.profraw`
- `docs/USB_SHORTCUT_FIX.md`

模型權重、Python 環境、`.runtime`、`.local-build` 與其他忽略的測試產物不進 Git。本次沒有刪除或回復以上排除項目。

## 本機分批提交（2026-10-21）

使用者已明確授權依修改內容分批建立 commit。分支為 `feat/local-tea-model-workflow`，僅本機提交，不 push。鍵盤變更、規則檔及測試產物留在工作區。

- `3487b1e`：feat: 強化自訂 ASR 連線測試並加入台灣模型探針。
- `eb09379`：feat: 加入本機整理護欄與單次雲端聊天傳輸。
- `25ddf2f`：feat: 由 App 管理本機 TEA 語音辨識引擎。
- `1f07c57`：fix: 恢復 VoiceInk Refine 第三方模型原名。
- `a4aedbb`：feat: 為本機語音模型清單加入中文與已安裝篩選。

模型候選範圍已在隔離副本未簽署 build-for-testing 通過，沒有納入未提交的鍵盤修改。Python 工具測試結果見下方驗證紀錄；最近 241 通過的完整 App 測試仍屬先前混合工作區，不冒充候選提交的完整宿主測試。

未重裝 App。commit 改變 HEAD 與來源指紋後，先前測試版的 CURRENT 收據不能沿用為最新提交的安裝證據；其程式碼亦含未提交鍵盤修改。下次需要驗收提交版本時，再由受支援安裝流程交付。

隔離候選契約測試：37 項通過。Python GGUF 工具 3 項通過；ASR 工具首輪 13 項有 1 項斷線測試失敗，後續查核結果：斷線測試單獨重跑通過，完整 13 項再跑通過；首輪失敗原因未確認。保留原始失敗日誌，不把重跑結果當成首輪全數通過。

### 候選範圍驗證

- 建置日誌：`/tmp/wagong-model-commit-candidate-build.log`。
- Python ASR 工具測試：`/tmp/wagong-model-batch-python-asr-tests.log`。
- Python GGUF 工具測試：`/tmp/wagong-model-batch-python-local-tests.log`。
- 本機 commit 均附 `Co-Authored-By: Codex <noreply@openai.com>` 與 `Human-Review: 僅下指令`。

## 剩餘項目納入版控（2026-10-21）

使用者已授權修正剩餘版控項目。鍵盤來源配對與狀態診斷、專案規則現已分批提交；`default.profraw` 停止追蹤，實際本機檔案仍保留，`*.profraw` 與 `*.profdata` 由 `.gitignore` 排除。

- `654dda0`：fix: 保守處理 USB 快速鍵的延遲來源配對。
- `5eefc27`：feat: 補齊鍵盤監控與裝置綁定診斷。
- `eb93581`：chore: 納入共用專案代理規則入口。

含鍵盤修改的完整候選來源未簽署建置通過，隔離契約測試 57 項、11 suites 通過，未啟動 App 宿主或替換目前 App。來源與測試日誌見 `docs/USB_SHORTCUT_FIX.md`。

本機 commit 均附 AI 協作與 `Human-Review: 僅下指令`。未 push、merge 或發布。規則內容保持原樣，只納入版控，未以本輪檔案核對代替 Claude Code／Codex 各自新主 session 的生效驗收。

同一把 USB 鍵盤、完整錄音與跨 App 交付仍待實機驗收；Gemini 逾時、Claude 輸出污染與模型清單改版待辦仍未修正。
