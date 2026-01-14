Para implementar a comunicação AXI4_Stream precisamos usar o TLAST até onde conheço. Fizemos a simulação comportamental e o TLAST estava funcionando exatamente como esperávamos. O sinal TLAST sempre sobe junto do penúltimo pixel e ele desce junto com a subida no frame_done, ou seja, frame_done sobre sincronizado com o último pixel. Portanto, nosso TLAST está sincronizado com o penúltimo pixel, conforme era esperado. 
Vamos adicionar o AXI4-Lite para controle/ status e como ferramenta de debug.
Quero que me acompanhe em cada etapa do encapsulamento do IP, na criação do AXI4-Stream.

Abaixo envio meu top_level atual:

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use work.hogpack.all;

entity hog_pipeline_link is
  port (
    clk : in  std_logic;
    rst : in  std_logic;

    frame_start : in std_logic;

    -- =========================
    -- Entrada: stream de pixels PADDED (PAD_SIZE x PAD_SIZE)
    -- =========================
    in_valid : in  std_logic;
    in_ready : out std_logic;
    pixel_in : in  unsigned(PIXEL_BITS-1 downto 0);

    -- =========================
    -- Saída: AXI4-Stream (descritor por frame)
    -- =========================
    m_axis_tdata  : out std_logic_vector(AXI_WORD_WIDTH-1 downto 0);
    m_axis_tvalid : out std_logic;
    m_axis_tready : in  std_logic;
    m_axis_tlast  : out std_logic;

    frame_done : out std_logic
  );
end entity;

architecture rtl of hog_pipeline_link is

  -- =========================
  -- (0) win_cross_taps -> taps cruz
  -- =========================
  signal t_valid, t_ready : std_logic;
  signal p12, p21, p23, p32 : unsigned(PIXEL_BITS-1 downto 0);

  -- =========================
  -- (1) grad_mag_bin -> (mag, bin)
  -- =========================
  signal gmb_valid, gmb_ready : std_logic;
  signal mag_tok : unsigned(MAG_BITS-1 downto 0);
  signal bin_tok : unsigned(3 downto 0);

  -- =========================
  -- (2) hog_cell_histogram -> (cell_idx, cell_hist)
  -- =========================
  signal cell_valid, cell_ready : std_logic;
  signal cell_idx  : unsigned(NUM_CELLS_BITS-1 downto 0);
  signal cell_hist : CellHist_t;

  -- =========================
  -- (3) hog_block_assemble -> block histogram (amplitude)
  -- =========================
  signal blk_valid, blk_ready : std_logic;
  signal blk_hist : BlockHist_t;

  -- =========================
  -- (4) block_binarize_v3 -> descritor binário por bloco
  -- =========================
  signal binblk_valid, binblk_ready : std_logic;
  signal bin_desc : std_logic_vector(HISTOGRAM_BITS_PER_BLOCK-1 downto 0);
  signal bin_valid      : std_logic;
  signal bin_in_ready   : std_logic;  -- in_ready do binarize (consome bloco)
  signal bin_out_ready  : std_logic;  -- in_ready do serializer (consome descritor)

begin

  -- =========================
  -- (0) Taps cruz (do padded -> ROI útil)
  -- =========================
  U_TAPS: entity work.win_cross_taps
    port map (
      clk => clk,
      rst => rst,
      frame_start => frame_start,

      in_valid => in_valid,
      in_ready => in_ready,
      pixel_in => pixel_in,

      out_valid => t_valid,
      out_ready => t_ready,

      p12 => p12,
      p21 => p21,
      p23 => p23,
      p32 => p32
    );

  -- =========================
  -- (1) Token combinado: grad + mag + bin
  -- =========================
  U_GMB : entity work.grad_mag_bin
    port map (
      clk => clk,
      rst => rst,

      in_valid => t_valid,
      in_ready => t_ready,

      p12 => p12,
      p21 => p21,
      p23 => p23,
      p32 => p32,

      out_valid => gmb_valid,
      out_ready => cell_ready,

      mag_out => mag_tok,
      bin_out => bin_tok
    );

  -- =========================
  -- (2) Histograma por célula
  -- =========================
  U_CELL : entity work.hog_cell_histogram
    port map (
      clk => clk,
      rst => rst,

      frame_start => frame_start,

      in_valid => gmb_valid,
      in_ready => cell_ready,
      mag_in   => mag_tok,
      bin_in   => bin_tok,

      out_valid     => cell_valid,
      out_ready     => blk_ready,
      cell_idx_out  => cell_idx,
      cell_hist_out => cell_hist
    );

  -- =========================
  -- (3) Montagem de bloco (stride 1 célula)
  -- =========================
  -- assemble (exemplo de conexão)
  U_BLK : entity work.hog_block_assemble
    port map (
      clk => clk,
      rst => rst,
      frame_start => frame_start,

      in_valid     => cell_valid,
      in_ready     => blk_ready,
      cell_idx_in  => cell_idx,
      cell_hist_in => cell_hist,

      out_valid      => blk_valid,
      out_ready      => bin_in_ready,     -- ? backpressure vem do binarize
      block_hist_out => blk_hist
    );

  -- binarize
  U_BIN : entity work.block_binarize_v3
    port map (
      clk => clk,
      rst => rst,
      frame_start => frame_start,

      in_valid      => blk_valid,
      in_ready      => bin_in_ready,      -- ?
      block_hist_in => blk_hist,

      out_valid    => bin_valid,
      out_ready    => bin_out_ready,      -- ? backpressure vem do serializer
      bin_desc_out => bin_desc
    );

  -- serializer
  U_SER : entity work.axis_block_serializer
    port map (
      clk => clk,
      rst => rst,
      frame_start => frame_start,

      in_valid => bin_valid,
      in_ready => bin_out_ready,          -- ?
      desc_in  => bin_desc,

      m_axis_tdata  => m_axis_tdata,
      m_axis_tvalid => m_axis_tvalid,
      m_axis_tready => m_axis_tready,
      m_axis_tlast  => m_axis_tlast,

      frame_done => frame_done
    );

end architecture;
