### 同じtbを用いて新しいrtlを作る時
target名を決める
filelists に<target>_sv.fや<target>_vhdl.fを追加する
src/rtlフォルダに作ったファイルを上記の.fに追加する
wrapperにtarget名に応じた `defineを定義する


### 新しいtbを追加する


---

## Makefile.cocotb の使い方

### 基本実行

```bash
cd simulation/
make -f Makefile.cocotb
```

デフォルト: `SIM=xcelium`, `TARGET=6Ops`, `TEST_UNIT=fp32_add`

### 波形表示(xrun)
```
XRUN_FLAGS := -v200x -64bit -sv -access +rwc -input "@run 150112ns; exit" -gui
```
にする


### パラメータ

| 変数 | デフォルト | 説明 |
|---|---|---|
| `SIM` | `xcelium` | シミュレータ（xceliumのみ対応） |
| `TARGET` | `6Ops` | ビルド対象RTL。Makefileと同一の選択肢が使える |
| `TEST_UNIT` | `fp32_add` | テスト対象。TOPLEVEL=`<TEST_UNIT>_wrapper`、MODULE=`<TEST_UNIT>_test` になる |

### TARGET の選択肢（Makefileと共通）

| `TARGET` | define |
|---|---|
| `v2_1_bf16_add` | `V2_1_BF16_ADD` |
| `v2_2_bf16_mult` | `V2_2_BF16_MULT` |
| `4Ops` | `FOUROPS` |
| `6Ops` | `SIXOPS` |
| `mixed_addmult` | `MIXED_ADDMULT` |

TARGETを変えた場合は対応する `filelists/cocotb/<TARGET>_sv.f` が必要。

```bash
# 例: v2_1_bf16_add ターゲットでbf16_addテストを実行
make -f Makefile.cocotb TARGET=v2_1_bf16_add TEST_UNIT=bf16_add

# 例: 4Ops ターゲットでfp32_addテストを実行
make -f Makefile.cocotb TARGET=4Ops TEST_UNIT=fp32_add
```

### TEST_UNIT の選択肢

| `TEST_UNIT` | テストスクリプト | DUT |
|---|---|---|
| `fp32_add` | `fp32_add_test.py` | `fp32_add_wrapper` |
| `fp32_mult` | `fp32_mult_test.py` | `fp32_mult_wrapper` |
| `bf16_add` | `bf16_add_test.py` | `bf16_add_wrapper` |
| `bf16_mult` | `bf16_mult_test.py` | `bf16_mult_wrapper` |
| `fp8_add` | `fp8_add_test.py` | `fp8_add_wrapper` (E4M3, 6Opsのみ) |
| `fp8_mult` | `fp8_mult_test.py` | `fp8_mult_wrapper` (E4M3, 6Opsのみ) |

```bash
# 例: bf16のaddテストを実行
make -f Makefile.cocotb TEST_UNIT=bf16_add
```

ビルド出力: `build/<SIM>/<TARGET>/<TEST_UNIT>_cocotb/results.xml`

### テストファイルの場所

- Pythonテスト: `src/tb/cocotb/<TEST_UNIT>_test.py`
- SVラッパー: `src/tb/cocotb_wrapper.sv`（全wrapper定義）
- ファイルリスト: `filelists/cocotb/<TARGET>_sv.f`

### 新しいテストを追加する時

1. `src/tb/cocotb/<test_unit>_test.py` を作成（`@cocotb.test()` で定義）
2. `src/tb/cocotb_wrapper.sv` に `<test_unit>_wrapper` moduleを追加
3. `make -f Makefile.cocotb TEST_UNIT=<test_unit>` で実行



make TARGET=original_sv TOP=tb_fpadd_fp32
