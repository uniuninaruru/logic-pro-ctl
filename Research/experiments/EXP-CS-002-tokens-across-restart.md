[日本語](EXP-CS-002-tokens-across-restart.md) | [English](EXP-CS-002-tokens-across-restart.en.md)

# EXP-CS-002：割り当てのリスト 16 の識別子は Logic の再起動をまたいで変わらない（設定ファイルのコピー、読み取りのみ）

詳細は [英語版](EXP-CS-002-tokens-across-restart.en.md)。10/21 のコピーと再起動後（10/24）のコピーで、7,985 件すべての識別子が一致し、重複もなし。中身が完全に同じ行は 490 件で、他は固定部分の +0x47 と +0x5e だけが違う（保存のたびに変わる欄で、識別には使えない）。CC 23 → Master Gain の行は状態ビット 3・4 と前回の値が消えており、読み込み時のリセットの予測と一致した。
