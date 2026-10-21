[日本語](EXP-CA-009-plugin-replacement-target.md) | [English](EXP-CA-009-plugin-replacement-target.en.md)

# EXP-CA-009：プラグインを差し替え・作り直し・2 つにしたとき、CC 23 はどのプラグインを動かすか（PLAN-CA-005 T3）

詳細は [英語版](EXP-CA-009-plugin-replacement-target.en.md)。静的解析（ASSIGN-IDENTITY-001）の予測 5 つがすべて当たった。

- T3a：Linear Phase EQ に差し替え → CC 23 は何も動かさない。
- T3b：外して新しい Channel EQ を入れる → 新しい方を動かす。
- T3c：スロット 4 にも Channel EQ を足す → 上のスロット 1 だけを動かす。
- T3d：スロット 1 を外す → スロット 4 の方に移る。
- T3e：スロット 1 にまた新しい Channel EQ を入れる → 上の新しい方に移る。

結論（仮説、確信度：この行については高）：固定トラック方式でない割り当ては、メッセージのたびに「選択中のトラックで、ID が同じプラグインのうちスロット順で最初のもの」を探す。インスタンスには張り付かず、保存された UUID も使わない。取り消し履歴で全部元に戻し、26 本のスライダーが基準値と一致することを確認した。
