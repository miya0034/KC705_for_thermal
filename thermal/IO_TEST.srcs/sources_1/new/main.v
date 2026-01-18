`timescale 1ns / 1ps
`default_nettype none

module main(
    // 200 MHz 差動クロック（constraint: SYSCLK_200MP_IN / SYSCLK_200MN_IN）
    input  wire        SYSCLK_200MP_IN,
    input  wire        SYSCLK_200MN_IN,   // 200 MHz

    // TDC 入力
    input  wire        IN1,
    input wire        IN2,
    input  wire        IN3,
    input  wire        IN4_p,
    input  wire        IN4_n,
    input  wire        IN5_p,
    input  wire        IN5_n,
    input  wire        IN6,

    // =============================
    //  SiTCP / Ethernet 用 追加 I/O
    // =============================

    // GMII (PHY RX → FPGA)
    input  wire        GMII_RX_CLK_IN,
    input  wire        GMII_RX_DV_IN,
    input  wire [7:0]  GMII_RXD_IN,
    input  wire        GMII_RX_ER_IN,
    input  wire        GMII_CRS_IN,
    input  wire        GMII_COL_IN,

    // GMII (FPGA TX → PHY)
    input  wire        GMII_TX_CLK_IN,     // constraint 上は入力クロック（設計上は未使用）
    output wire        GMII_TX_EN_OUT,
    output wire [7:0]  GMII_TXD_OUT,
    output wire        GMII_TX_ER_OUT,
    output wire        GMII_GTXCLK_OUT,    // PHY へ出す 125 MHz クロック

    // PHY Reset
    output wire        GMII_RSTn_OUT,

    // MDIO / MDC
    inout  wire        GMII_MDIO_IO,
    output wire        GMII_MDC_OUT,

    // EEPROM I2C
    inout  wire        I2C_SDA_IO,
    output wire        I2C_SCL_OUT,

    // スイッチ類
    input  wire        SW_N_IN,            // プッシュスイッチ（今回のコードでは未使用）
    input  wire [3:0]  GPIO_DIP_SW_IN      // DIP SW[3] で IP 固定／EEPROM 切り替え
);

    //==========================================================
    // クロック生成まわり
    //==========================================================
    wire resetn = 1'b1;       // clk_wiz の active-low reset
    wire clk_out1;            // 250 MHz 想定（TDC 用）
    wire OSC;                 // 200 MHz（システム・SiTCP 用）
    wire clk125M;             // 125 MHz（GMII TX 用）
    wire locked;

    // SiTCP 系の「システムリセット」（PLL lock 後 1）
    wire SYS_RSTn;
    assign SYS_RSTn = locked;

    wire clk_out;
    assign clk_out = clk_out1;

    // 差動入力 → 単端子
    wire IN4;
    wire IN5;

    IBUFDS #(
        .DIFF_TERM("TRUE"),
        .IBUF_LOW_PWR("FALSE")
    ) IBUFDS_IN4 (
        .I (IN4_p),
        .IB(IN4_n),
        .O (IN4)
    );

    IBUFDS #(
        .DIFF_TERM("TRUE"),
        .IBUF_LOW_PWR("FALSE")
    ) IBUFDS_IN5 (
        .I (IN5_p),
        .IB(IN5_n),
        .O (IN5)
    );

    // クロック生成: 250 MHz, 200 MHz, 125 MHz
    clk_wiz_0 clk_wiz (
        .clk_out1(clk_out1),        // 250 MHz (TDC 側)
        .clk_out2(OSC),             // 200 MHz (System / SiTCP)
        .clk_out3(clk125M),         // 125 MHz (GMII TX 用)
        .resetn  (resetn),
        .locked  (locked),
        .clk_in1_p(SYSCLK_200MP_IN),
        .clk_in1_n(SYSCLK_200MN_IN)
    );

/*    //==========================================================
    // OUT2: 200MHz に同期し，200nsに1回，6クロック分だけ High の矩形波
    //   - OSC = 200 MHz (周期 5 ns)
    //   - 200 ns = 40 クロック
    //   - 0〜5 の 6 クロックの間だけ OUT2=1，それ以外は 0
    //==========================================================
    reg [5:0] out2_cnt = 6'd0;   // 0〜39
    reg       out2_reg = 1'b0;   // OUT2 の内部レジスタ

    always @(posedge OSC or negedge SYS_RSTn) begin
        if (!SYS_RSTn) begin
            out2_cnt <= 6'd0;
            out2_reg <= 1'b0;
        end else begin
            // 0〜39 でカウント（200ns = 40clk）
            if (out2_cnt == 6'd39)
                out2_cnt <= 6'd0;
            else
                out2_cnt <= out2_cnt + 6'd1;

            // 0〜5 の 6 クロック間だけ High
            if (out2_cnt == 6'd0)
                out2_reg <= 1'b1;   // パルス開始（立ち上がり）
            else if (out2_cnt == 6'd6)
                out2_reg <= 1'b0;   // パルス終了（立ち下がり）
        end
    end

    assign OUT2 = out2_reg;
*/
    //==========================================================
    // TDC → 64bit → 8bit クロスドメイン FIFO まで
    //==========================================================
    wire [7:0] dout_8bit_ext;
    wire       valid_ext;
    wire       rd_rq;
    wire [2:0] IP;
    

    fifo_output fifo_out (
        .IN1   (IN1),
        .IN2   (IN2),
        .IN3   (IN3),
        .IN4   (IN4),
        .IN5   (IN5),
        .IN6   (IN6),
        .clk_out(clk_out),    // 250 MHz 書き込み側
        .OSC   (OSC),         // 200 MHz 読み出し側
        .locked(locked),

        .dout_8bit_ext(dout_8bit_ext),  // 200 MHz ドメイン 8bit
        .valid_ext   (valid_ext),       // 1クロック有効

        .clk125M(clk125M),              // いまは未使用でもよい（将来用）
        .rd_rq  (rd_rq),
        .IP(IP)                 // packet_builder からの read 要求
    );

    //==========================================================
    // パケット生成（1イベント=64bit → Header+Payload+Footer）
    //==========================================================
    wire [7:0] packet;
    wire       tx_we;
    wire       packet_done;

    // 注意: packet_builder は 200 MHz (OSC) ドメインで駆動
    packet_builder pb (
        .OSC           (OSC),
        .dout_8bit_ext (dout_8bit_ext),
        .valid         (valid_ext),
        .rd_rq         (rd_rq),        // FIFO に対する read 要求
        .packet2       (packet),       // SiTCP へ渡す 8bit データ
        .tx_we2        (tx_we),        // 1クロック write パルス
        .packet_done   (packet_done),
        .TCP_TX_FULL   (TCP_TX_FULL)
    );

    //==========================================================
    // MDIO IOBUF
    //==========================================================
    wire GMII_MDIO_IN;
    wire GMII_MDIO_OUT;
    wire GMII_MDIO_OE;

    IOBUF mdio_buf (
        .O (GMII_MDIO_IN),    // PHY → FPGA
        .IO(GMII_MDIO_IO),    // ピン
        .I (GMII_MDIO_OUT),   // FPGA → PHY
        .T (~GMII_MDIO_OE)    // OE=1 のとき出力, OE=0 で High-Z
    );

    //==========================================================
    // GMII TX クロック生成 (125 MHz)
    //==========================================================
    wire clk125M_bufg;

    BUFG bufg_clk125M (
        .I(clk125M),
        .O(clk125M_bufg)
    );

    // PHY へ出す GTXCLK: 125 MHz の DDR トグル
    ODDR #(
        .DDR_CLK_EDGE("SAME_EDGE")
    ) ODDR_GTXCLK (
        .Q (GMII_GTXCLK_OUT),
        .C (clk125M_bufg),
        .CE(1'b1),
        .D1(1'b1),   // High
        .D2(1'b0),   // Low
        .R (1'b0),
        .S (1'b0)
    );

    //==========================================================
    // SiTCP ラッパ WRAP_SiTCP_GMII_XC7K_32K インスタンス
    //==========================================================

    // SiTCP 内部制御用
    wire        SiTCP_RST;

    // TCP IF
    wire        TCP_OPEN_ACK;
    wire        TCP_CLOSE_REQ;
    wire        TCP_ERROR;
    wire        TCP_TX_FULL;
    wire        TCP_RX_WR;
    wire [7:0]  TCP_RX_DATA;

    // FIFO write count (Rx 側) 今回は未使用なので「十分空きあり」と見せる
    wire [15:0] TCP_RX_WC = 16'hFFFF;

    // TX: packet_builder からのデータを直接接続
    wire        TCP_TX_WR;
    wire [7:0]  TCP_TX_DATA;

    assign TCP_TX_WR   = tx_we;
    assign TCP_TX_DATA = packet;
    // 本来は TCP_TX_FULL を見て flow control するべき（今は未対策）

    // TCP connection control
    wire TCP_OPEN_REQ = 1'b0;          // サーバーモード固定
    wire TCP_CLOSE_ACK;

    assign TCP_CLOSE_ACK = TCP_CLOSE_REQ;

    // RBCP（今回は使わないのでダミー実装）
    wire        RBCP_ACT;
    wire [31:0] RBCP_ADDR;
    wire [7:0]  RBCP_WD;
    wire        RBCP_WE;
    wire        RBCP_RE;
    wire        RBCP_ACK;
    wire [7:0]  RBCP_RD;

    assign RBCP_ACK = 1'b1;
    assign RBCP_RD  = 8'h00;

    // EEPROM ライン（今度は実際に使用）
    wire EEPROM_CS;
    wire EEPROM_SK;
    wire EEPROM_DI;
    wire EEPROM_DO;
    wire RST_EEPROM;   // EEPROM 初期化完了まで 1, 終了で 0

    // ユーザー定義レジスタ（未使用）
    wire [7:0] USR_REG_X3C;
    wire [7:0] USR_REG_X3D;
    wire [7:0] USR_REG_X3E;
    wire [7:0] USR_REG_X3F;

    // GMII モード指定
    wire GMII_1000M = 1'b1;  // 常に 1Gbps モード (GMII)

    //==========================================================
    // IP / TCP / RBCP の設定
    //   DIP_SW[3] = 0 → すべて EEPROM (DEFAULT_*)
    //   DIP_SW[3] = 1 → IP だけ 192.168.10.30 に固定
    //==========================================================

    // IP の固定値: 192.168.10.30 = C0.A8.0A.1E
    localparam [31:0] FIXED_IP_ADDR   = 32'hC0A8_0A1E;

    // EXT_* は DIP_SW[3] に応じて切り替え
    wire [31:0] EXT_IP_ADDR;
    wire [15:0] EXT_TCP_PORT;
    wire [15:0] EXT_RBCP_PORT;

    // DIP_SW[3] = 0 → EXT_IP_ADDR = 0 → DEFAULT_IP_ADDR (EEPROM)
    // DIP_SW[3] = 1 → EXT_IP_ADDR = FIXED_IP_ADDR → 192.168.10.30
    assign EXT_IP_ADDR   = GPIO_DIP_SW_IN[3] ? FIXED_IP_ADDR : 32'd0;

    // TCP/RBCP は常に EEPROM (DEFAULT_*) を使う
    assign EXT_TCP_PORT  = 16'd0;
    assign EXT_RBCP_PORT = 16'd0;

    localparam [4:0]  PHY_ADDR       = 5'd0;     // KC705 PHY アドレス 0

    //==========================================================
    // EEPROM I2C 制御ブロック（AT93C46_IIC）
    //   - CLK_IN   : 200 MHz (OSC)
    //   - RESET_IN : active high reset = ~SYS_RSTn
    //   - IIC_INIT_OUT = RST_EEPROM を SiTCP の RST へ接続
    //==========================================================
    AT93C46_IIC #(
        .PCA9548_AD (7'b1110_100),   // PCA9548 Device Address
        .PCA9548_SL (8'b0000_1000),  // PCA9548 Select code (Ch3,Ch4 enable)
        .IIC_MEM_AD (7'b1010_100),   // IIC Memory Device Address
        .FREQUENCY  (8'd200),        // CLK_IN Frequency [MHz] (>10MHz)
        .DRIVE      (4),             // Output Buffer Strength
        .IOSTANDARD ("LVCMOS25"),    // I/O Standard
        .SLEW       ("SLOW")         // Output buffer Slew rate
    )
    u_AT93C46_IIC (
        .CLK_IN       (OSC),          // System Clock (200 MHz)
        .RESET_IN     (~SYS_RSTn),    // Reset (PLL lock 前は 1)
        .IIC_INIT_OUT (RST_EEPROM),   // IIC, AT93C46 Initialize (0 = Initialize End)

        .EEPROM_CS_IN (EEPROM_CS),    // AT93C46 Chip select
        .EEPROM_SK_IN (EEPROM_SK),    // AT93C46 Serial data clock
        .EEPROM_DI_IN (EEPROM_DI),    // AT93C46 Serial write data (Master to Memory)
        .EEPROM_DO_OUT(EEPROM_DO),    // AT93C46 Serial read data (Slave to Master)

        .INIT_ERR_OUT (),             // PCA9548 Initialize Error

        // ch0 I2C アクセスは今回は未使用
        .IIC_REQ_IN   (1'b0),
        .IIC_NUM_IN   (8'h00),
        .IIC_DAD_IN   (7'b0),
        .IIC_ADR_IN   (8'b0),
        .IIC_RNW_IN   (1'b0),
        .IIC_WDT_IN   (8'b0),
        .IIC_RAK_OUT  (),
        .IIC_WDA_OUT  (),
        .IIC_WAE_OUT  (),
        .IIC_BSY_OUT  (),
        .IIC_RDT_OUT  (),
        .IIC_RVL_OUT  (),
        .IIC_EOR_OUT  (),
        .IIC_ERR_OUT  (),

        // Device Interface (I2C ピンへ接続)
        .IIC_SCL_OUT  (I2C_SCL_OUT),
        .IIC_SDA_IO   (I2C_SDA_IO)
    );

    WRAP_SiTCP_GMII_XC7K_32K #(
        .TIM_PERIOD(8'd200)  // システムクロック 200 MHz
    ) sitcp_inst (
        .CLK            (OSC),             // 200 MHz system clock
        .RST            (RST_EEPROM),      // EEPROM 初期化完了までリセット

        // Configuration parameters
        .FORCE_DEFAULTn (1'b1),            // 常に 1: ForceDefault モードは使わない
        .EXT_IP_ADDR    (EXT_IP_ADDR),     // DIP_SW[3] で 0 / 固定 IP を切り替え
        .EXT_TCP_PORT   (EXT_TCP_PORT),    // 常に 0 → DEFAULT_TCP_PORT (EEPROM)
        .EXT_RBCP_PORT  (EXT_RBCP_PORT),   // 常に 0 → DEFAULT_RBCP_PORT (EEPROM)
        .PHY_ADDR       (PHY_ADDR),

        // EEPROM
        .EEPROM_CS      (EEPROM_CS),
        .EEPROM_SK      (EEPROM_SK),
        .EEPROM_DI      (EEPROM_DI),
        .EEPROM_DO      (EEPROM_DO),
        .USR_REG_X3C    (USR_REG_X3C),
        .USR_REG_X3D    (USR_REG_X3D),
        .USR_REG_X3E    (USR_REG_X3E),
        .USR_REG_X3F    (USR_REG_X3F),

        // MII / GMII interface
        .GMII_RSTn      (GMII_RSTn_OUT),
        .GMII_1000M     (GMII_1000M),

        // TX
        .GMII_TX_CLK    (clk125M_bufg),   // 125 MHz TX クロック（外部 GMII_TX_CLK_IN は未使用）
        .GMII_TX_EN     (GMII_TX_EN_OUT),
        .GMII_TXD       (GMII_TXD_OUT),
        .GMII_TX_ER     (GMII_TX_ER_OUT),

        // RX
        .GMII_RX_CLK    (GMII_RX_CLK_IN),
        .GMII_RX_DV     (GMII_RX_DV_IN),
        .GMII_RXD       (GMII_RXD_IN),
        .GMII_RX_ER     (GMII_RX_ER_IN),
        .GMII_CRS       (GMII_CRS_IN),
        .GMII_COL       (GMII_COL_IN),

        // MDIO
        .GMII_MDC       (GMII_MDC_OUT),
        .GMII_MDIO_IN   (GMII_MDIO_IN),
        .GMII_MDIO_OUT  (GMII_MDIO_OUT),
        .GMII_MDIO_OE   (GMII_MDIO_OE),

        // User I/F
        .SiTCP_RST      (SiTCP_RST),

        // TCP connection control
        .TCP_OPEN_REQ   (TCP_OPEN_REQ),
        .TCP_OPEN_ACK   (TCP_OPEN_ACK),
        .TCP_ERROR      (TCP_ERROR),
        .TCP_CLOSE_REQ  (TCP_CLOSE_REQ),
        .TCP_CLOSE_ACK  (TCP_CLOSE_ACK),

        // FIFO I/F (RX from PC)
        .TCP_RX_WC      (TCP_RX_WC),
        .TCP_RX_WR      (TCP_RX_WR),
        .TCP_RX_DATA    (TCP_RX_DATA),

        // FIFO I/F (TX to PC)
        .TCP_TX_FULL    (TCP_TX_FULL),
        .TCP_TX_WR      (TCP_TX_WR),
        .TCP_TX_DATA    (TCP_TX_DATA),

        // RBCP
        .RBCP_ACT       (RBCP_ACT),
        .RBCP_ADDR      (RBCP_ADDR),
        .RBCP_WD        (RBCP_WD),
        .RBCP_WE        (RBCP_WE),
        .RBCP_RE        (RBCP_RE),
        .RBCP_ACK       (RBCP_ACK),
        .RBCP_RD        (RBCP_RD)
    );

endmodule

`default_nettype wire
