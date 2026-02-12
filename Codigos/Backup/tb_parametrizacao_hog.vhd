library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.textio.all;
use ieee.std_logic_textio.all;

use work.hogpack.all;

entity tb_parametrizacao_hog is
end entity;

architecture sim of tb_parametrizacao_hog is

  constant CLK_PERIOD : time := 10 ns;

  -- =====================================================
  -- CONFIGURAÇÃO DE TESTE
  -- =====================================================
  constant BASE_DIR : string :=
    "C:\Users\Natan\Documents\Codigos_Python\sim_inputs\";

  constant N_FRAMES : integer := 3;  -- poucos frames, foco estrutural
  constant MAX_CYCLES_PER_FRAME : integer := 1_000_000;

  -- =====================================================
  -- CLOCK / RESET
  -- =====================================================
  signal clk : std_logic := '0';
  signal rst : std_logic := '1';
  signal frame_start : std_logic := '0';

  -- =====================================================
  -- PIXEL INPUT
  -- =====================================================
  signal in_valid : std_logic := '0';
  signal in_ready : std_logic;
  signal pixel_in : unsigned(PIXEL_BITS-1 downto 0) := (others => '0');

  -- =====================================================
  -- AXI OUTPUT
  -- =====================================================
  signal m_axis_tdata  : std_logic_vector(AXI_WORD_WIDTH-1 downto 0);
  signal m_axis_tvalid : std_logic;
  signal m_axis_tready : std_logic := '1';
  signal m_axis_tlast  : std_logic;
  signal frame_done    : std_logic;

begin

  clk <= not clk after CLK_PERIOD/2;

  -- =====================================================
  -- DUT
  -- =====================================================
  UUT : entity work.hog_pipeline_link
    port map (
      clk => clk,
      rst => rst,
      frame_start => frame_start,

      in_valid => in_valid,
      in_ready => in_ready,
      pixel_in => pixel_in,

      m_axis_tdata  => m_axis_tdata,
      m_axis_tvalid => m_axis_tvalid,
      m_axis_tready => m_axis_tready,
      m_axis_tlast  => m_axis_tlast,

      frame_done => frame_done
    );

  -- =====================================================
  -- PROCESSO PRINCIPAL
  -- =====================================================
  process
    file f_in : text;
    variable L : line;

    variable pix_slv : std_logic_vector(PIXEL_BITS-1 downto 0);

    variable sent_pixels : integer;
    variable recv_words  : integer;
    variable cycles      : integer;

  begin
    -- RESET
    rst <= '1';
    frame_start <= '0';
    in_valid <= '0';
    pixel_in <= (others => '0');

    wait for 100 ns;
    wait until rising_edge(clk);
    rst <= '0';
    wait until rising_edge(clk);

    report "============================================";
    report "INICIO TESTE DE PARAMETRIZACAO";
    report "ROI_SIZE      = " & integer'image(ROI_SIZE);
    report "BLOCK_SIDE    = " & integer'image(BLOCK_SIDE);
    report "TOTAL_PIXELS  = " & integer'image(TOTAL_PIXELS_IN);
    report "NUM_WORDS     = " & integer'image(NUM_WORDS);
    report "============================================";

    for frame_id in 0 to N_FRAMES-1 loop

      -- abre arquivo de pixels
      file_open(
        f_in,
        BASE_DIR & "frame_" &
        integer'image(frame_id) & "_roi_000_pixels.txt",
        read_mode
      );

      -- inicia frame
      frame_start <= '1';
      wait until rising_edge(clk);
      frame_start <= '0';

      sent_pixels := 0;
      recv_words  := 0;
      cycles      := 0;
      in_valid    <= '0';

      while cycles < MAX_CYCLES_PER_FRAME loop
        wait until rising_edge(clk);
        cycles := cycles + 1;

        -- =====================================
        -- ENVIO DE PIXELS
        -- =====================================
        if sent_pixels < TOTAL_PIXELS_IN then
          if in_valid = '0' then
            readline(f_in, L);
            read(L, pix_slv);
            pixel_in <= unsigned(pix_slv);
            in_valid <= '1';
          elsif in_ready = '1' then
            sent_pixels := sent_pixels + 1;
            in_valid <= '0';
          end if;
        else
          in_valid <= '0';
        end if;

        -- =====================================
        -- RECEPÇÃO AXI
        -- =====================================
        if m_axis_tvalid = '1' and m_axis_tready = '1' then
          if recv_words = NUM_WORDS-1 then
            assert m_axis_tlast = '1'
              report "ERRO: TLAST esperado no ultimo word"
              severity failure;
          else
            assert m_axis_tlast = '0'
              report "ERRO: TLAST prematuro"
              severity failure;
          end if;

          recv_words := recv_words + 1;
        end if;

        exit when recv_words = NUM_WORDS;
      end loop;

      file_close(f_in);

      -- =====================================
      -- ASSERTS FINAIS DO FRAME
      -- =====================================
      assert sent_pixels = TOTAL_PIXELS_IN
        report "ERRO: PIXELS ENVIADOS != TOTAL_PIXELS_IN"
        severity failure;

      assert recv_words = NUM_WORDS
        report "ERRO: WORDS RECEBIDOS != NUM_WORDS"
        severity failure;

      assert cycles < MAX_CYCLES_PER_FRAME
        report "ERRO: TIMEOUT NO FRAME"
        severity failure;

      report "FRAME " & integer'image(frame_id) &
             " OK | pixels=" & integer'image(sent_pixels) &
             " | words=" & integer'image(recv_words);

      wait for 50 ns;
    end loop;

    report "============================================";
    report "TESTE DE PARAMETRIZACAO FINALIZADO COM SUCESSO";
    report "============================================";

    wait;
  end process;

end architecture;
