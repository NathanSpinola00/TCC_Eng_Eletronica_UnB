-- ============================================================================
-- tb_parametrizacao.vhd  (TOP de simulação)
--
-- Validação ESTRUTURAL da parametrização (hogpack):
--  - Envia exatamente TOTAL_PIXELS_IN pixels (PAD_SIZE x PAD_SIZE)
--  - Captura exatamente NUM_WORDS words AXI
--  - TLAST apenas no último word (NUM_WORDS-1)
--  - Detecta deadlock/timeout
--  - frame_done deve ser observado (latch robusto)
--  - Gera LOG em arquivo "tb_param_log.txt"
--
-- Entrada:
--  - Se ROI_SIZE = 64: usa arquivo fixo:
--      C:/Users/Natan/Documents/Codigos_Python/roi_66x66_padded_pixels.txt
--  - Caso contrário (ex.: ROI=32): usa padrão no diretório atual:
--      frame_0000_roi_000_pixels.txt
--
-- Importante (XSIM):
--  - got_words: driver único no monitor
--  - idle_cycles/total_cycles: driver único no watchdog
--  - resets por frame feitos via frame_start dentro do próprio processo driver
-- ============================================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.textio.all;
use ieee.std_logic_textio.all;

use work.hogpack.all;

entity tb_parametrizacao is
end entity;

architecture sim of tb_parametrizacao is

  constant CLK_PERIOD : time := 10 ns;

  constant N_FRAMES   : integer := 3;
  constant ROI_ID     : integer := 0;

  -- ROI=64 (PAD=66) caminho fixo
  constant INPUT_DIR_64 : string := "C:/Users/Natan/Documents/Codigos_Python/";
  constant FILE_64      : string := "roi_66x66_padded_pixels.txt";

  -- ROI != 64: padrão no diretório atual
  constant INPUT_DIR_DEFAULT : string := "";

  -- Watchdogs (ciclos)
  constant WDOG_MAX_IDLE_CYCLES  : integer := 200000;
  constant WDOG_MAX_TOTAL_CYCLES : integer := 2000000;

  -- DUT I/O
  signal clk         : std_logic := '0';
  signal rst         : std_logic := '1';
  signal frame_start : std_logic := '0';

  signal in_valid : std_logic := '0';
  signal in_ready : std_logic;
  signal pixel_in : unsigned(PIXEL_BITS-1 downto 0) := (others => '0');

  signal m_axis_tdata  : std_logic_vector(AXI_WORD_WIDTH-1 downto 0);
  signal m_axis_tvalid : std_logic;
  signal m_axis_tready : std_logic := '1';
  signal m_axis_tlast  : std_logic;
  signal frame_done    : std_logic;

  -- Handshakes
  signal in_hs  : std_logic := '0';
  signal out_hs : std_logic := '0';

  -- Contadores
  signal sent_pixels : integer := 0;   -- driver único no p_main
  signal got_words   : integer := 0;   -- driver único no p_out_monitor

  -- Watchdogs
  signal idle_cycles  : integer := 0;  -- driver único no p_watchdog
  signal total_cycles : integer := 0;  -- driver único no p_watchdog

  -- frame_done latch (robusto p/ pulso curto)
  signal frame_done_seen : std_logic := '0';

  -- =========================
  -- Funções auxiliares
  -- =========================
  function to_4digits(n : integer) return string is
    variable s : string(1 to 4);
    variable v : integer := n;
  begin
    if v < 0 then v := 0; end if;
    s(4) := character'val(character'pos('0') + (v mod 10)); v := v / 10;
    s(3) := character'val(character'pos('0') + (v mod 10)); v := v / 10;
    s(2) := character'val(character'pos('0') + (v mod 10)); v := v / 10;
    s(1) := character'val(character'pos('0') + (v mod 10));
    return s;
  end function;

  function to_3digits(n : integer) return string is
    variable s : string(1 to 3);
    variable v : integer := n;
  begin
    if v < 0 then v := 0; end if;
    s(3) := character'val(character'pos('0') + (v mod 10)); v := v / 10;
    s(2) := character'val(character'pos('0') + (v mod 10)); v := v / 10;
    s(1) := character'val(character'pos('0') + (v mod 10));
    return s;
  end function;

begin

  -- Clock
  clk <= not clk after CLK_PERIOD/2;

  -- Handshakes
  in_hs  <= '1' when (in_valid = '1' and in_ready = '1') else '0';
  out_hs <= '1' when (m_axis_tvalid = '1' and m_axis_tready = '1') else '0';

  -- DUT
  dut: entity work.hog_pipeline_link
    port map (
      clk         => clk,
      rst         => rst,
      frame_start => frame_start,

      in_valid    => in_valid,
      in_ready    => in_ready,
      pixel_in    => pixel_in,

      m_axis_tdata  => m_axis_tdata,
      m_axis_tvalid => m_axis_tvalid,
      m_axis_tready => m_axis_tready,
      m_axis_tlast  => m_axis_tlast,

      frame_done => frame_done
    );

  -- Latch do frame_done (robusto)
  p_frame_done_seen: process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        frame_done_seen <= '0';
      else
        if frame_start = '1' then
          frame_done_seen <= '0';
        elsif frame_done = '1' then
          frame_done_seen <= '1';
        end if;
      end if;
    end if;
  end process;

  -- Watchdog anti-deadlock (driver ÚNICO de idle_cycles e total_cycles)
  p_watchdog: process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        idle_cycles  <= 0;
        total_cycles <= 0;
      else
        -- reset por frame (evita múltiplos drivers)
        if frame_start = '1' then
          idle_cycles  <= 0;
          total_cycles <= 0;
        else
          total_cycles <= total_cycles + 1;

          if (in_hs = '1') or (out_hs = '1') then
            idle_cycles <= 0;
          else
            idle_cycles <= idle_cycles + 1;
          end if;

          assert idle_cycles < WDOG_MAX_IDLE_CYCLES
            report "TIMEOUT/DEADLOCK: sem handshake (in/out) por muito tempo (idle_cycles="
                   & integer'image(idle_cycles) & ")"
            severity failure;

          assert total_cycles < WDOG_MAX_TOTAL_CYCLES
            report "TIMEOUT: frame excedeu limite total de ciclos (total_cycles="
                   & integer'image(total_cycles) & ")"
            severity failure;
        end if;
      end if;
    end if;
  end process;

  -- Monitor da saída: conta words e valida TLAST (driver ÚNICO de got_words)
  p_out_monitor: process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        got_words <= 0;
      else
        -- reset por frame (evita múltiplos drivers)
        if frame_start = '1' then
          got_words <= 0;
        else
          if out_hs = '1' then
            assert not (m_axis_tlast = '1' and got_words /= (NUM_WORDS - 1))
              report "TLAST PREMATURO: TLAST='1' no word_index="
                     & integer'image(got_words)
                     & " (esperado somente em "
                     & integer'image(NUM_WORDS - 1) & ")"
              severity failure;

            if got_words = (NUM_WORDS - 1) then
              assert (m_axis_tlast = '1')
                report "TLAST AUSENTE: no ultimo word_index="
                       & integer'image(got_words) & " (NUM_WORDS-1)"
                severity failure;
            else
              assert (m_axis_tlast = '0')
                report "TLAST INVALIDO: TLAST='1' fora do ultimo word (word_index="
                       & integer'image(got_words) & ")"
                severity failure;
            end if;

            got_words <= got_words + 1;
          end if;
        end if;
      end if;
    end if;
  end process;

  -- Sequência principal + LOG EM ARQUIVO
  p_main: process
    file f_in  : text;
    file flog  : text;

    variable ln : line;
    variable L  : line;

    variable pix_slv : std_logic_vector(PIXEL_BITS-1 downto 0);

    -- Nome de arquivo fixo (VRFC-friendly)
    variable fname     : string(1 to 512);
    variable fname_len : integer;

    -- Constantes literais para compor nome padrão
    constant L_FRAME : string := "frame_";
    constant L_ROI   : string := "_roi_";
    constant L_PIX   : string := "_pixels.txt";

    procedure pulse_frame_start is
    begin
      frame_start <= '1';
      wait until rising_edge(clk);
      frame_start <= '0';
      wait until rising_edge(clk);
    end procedure;

    procedure file_close_safe is
    begin
      file_close(f_in);
    end procedure;

    procedure log_params is
    begin
      write(L, string'("TB PARAMETRIZACAO - LOG")); writeline(flog, L);
      write(L, string'("--------------------------------------------------")); writeline(flog, L);

      write(L, string'("ROI_SIZE=")); write(L, ROI_SIZE);
      write(L, string'("  BLOCK_SIDE=")); write(L, BLOCK_SIDE);
      write(L, string'("  PADDING=")); write(L, PADDING);
      write(L, string'("  PAD_SIZE=")); write(L, PAD_SIZE);
      writeline(flog, L);

      write(L, string'("TOTAL_PIXELS_IN=")); write(L, TOTAL_PIXELS_IN);
      write(L, string'("  NUM_CELLS_X=")); write(L, NUM_CELLS_X);
      write(L, string'("  NUM_CELLS_Y=")); write(L, NUM_CELLS_Y);
      write(L, string'("  TOTAL_BLOCKS=")); write(L, TOTAL_BLOCKS);
      writeline(flog, L);

      write(L, string'("HISTOGRAM_BITS_PER_BLOCK=")); write(L, HISTOGRAM_BITS_PER_BLOCK);
      write(L, string'("  WORDS_PER_BLOCK=")); write(L, WORDS_PER_BLOCK);
      write(L, string'("  NUM_WORDS=")); write(L, NUM_WORDS);
      writeline(flog, L);

      write(L, string'("--------------------------------------------------")); writeline(flog, L);
    end procedure;

    procedure open_input_file(frame_id : integer; roi_id : integer) is
      variable f4 : string(1 to 4);
      variable r3 : string(1 to 3);
      variable i  : integer;
    begin
      fname := (others => ' ');
      fname_len := 0;

      if ROI_SIZE = 64 then
        for i in INPUT_DIR_64'range loop
          fname_len := fname_len + 1;
          fname(fname_len) := INPUT_DIR_64(i);
        end loop;
        for i in FILE_64'range loop
          fname_len := fname_len + 1;
          fname(fname_len) := FILE_64(i);
        end loop;

      else
        f4 := to_4digits(frame_id);
        r3 := to_3digits(roi_id);

        for i in INPUT_DIR_DEFAULT'range loop
          fname_len := fname_len + 1;
          fname(fname_len) := INPUT_DIR_DEFAULT(i);
        end loop;

        for i in L_FRAME'range loop
          fname_len := fname_len + 1;
          fname(fname_len) := L_FRAME(i);
        end loop;

        for i in f4'range loop
          fname_len := fname_len + 1;
          fname(fname_len) := f4(i);
        end loop;

        for i in L_ROI'range loop
          fname_len := fname_len + 1;
          fname(fname_len) := L_ROI(i);
        end loop;

        for i in r3'range loop
          fname_len := fname_len + 1;
          fname(fname_len) := r3(i);
        end loop;

        for i in L_PIX'range loop
          fname_len := fname_len + 1;
          fname(fname_len) := L_PIX(i);
        end loop;
      end if;

      assert fname_len <= fname'length
        report "Caminho do arquivo muito grande (fname_len="
               & integer'image(fname_len) & ")"
        severity failure;

      write(L, string'("Abrindo arquivo de entrada: "));
      write(L, fname(1 to fname_len));
      writeline(flog, L);

      file_open(f_in, fname(1 to fname_len), read_mode);
    end procedure;

  begin
    -- init
    in_valid      <= '0';
    pixel_in      <= (others => '0');
    frame_start   <= '0';
    m_axis_tready <= '1';

    -- reset
    rst <= '1';
    wait for 20*CLK_PERIOD;
    wait until rising_edge(clk);
    rst <= '0';
    wait until rising_edge(clk);

    -- abre log
    file_open(flog, "tb_param_log.txt", write_mode);
    log_params;

    -- frames
    for fr in 0 to N_FRAMES-1 loop

      -- zera contador de pixels por frame (driver único aqui)
      sent_pixels <= 0;

      write(L, string'("Frame ")); write(L, fr);
      write(L, string'(": START"));
      writeline(flog, L);

      open_input_file(fr, ROI_ID);

      -- frame_start: também reseta got_words/idle_cycles/total_cycles nos processos deles
      pulse_frame_start;

      -- garante 1 ciclo após frame_start
      wait until rising_edge(clk);

      -- envia TOTAL_PIXELS_IN pixels
      for p in 0 to TOTAL_PIXELS_IN-1 loop
        if endfile(f_in) then
          assert false
            report "Arquivo terminou antes de TOTAL_PIXELS_IN. Frame="
                   & integer'image(fr)
                   & " pixel_index=" & integer'image(p)
            severity failure;
        end if;

        readline(f_in, ln);
        read(ln, pix_slv);

        pixel_in <= unsigned(pix_slv);
        in_valid <= '1';

        wait until rising_edge(clk);
        while in_ready /= '1' loop
          wait until rising_edge(clk);
        end loop;

        sent_pixels <= sent_pixels + 1;
        in_valid <= '0';
      end loop;

      -- encerra entrada
      in_valid <= '0';
      pixel_in <= (others => '0');
      file_close_safe;

      -- valida contagem de pixels
      wait until rising_edge(clk);
      assert sent_pixels = TOTAL_PIXELS_IN
        report "ERRO: sent_pixels != TOTAL_PIXELS_IN. sent_pixels="
               & integer'image(sent_pixels)
               & " TOTAL_PIXELS_IN=" & integer'image(TOTAL_PIXELS_IN)
        severity failure;

      -- aguarda words de saída
      while got_words < NUM_WORDS loop
        wait until rising_edge(clk);
      end loop;

      -- valida contagem de words
      wait until rising_edge(clk);
      assert got_words = NUM_WORDS
        report "ERRO: got_words != NUM_WORDS. got_words="
               & integer'image(got_words)
               & " NUM_WORDS=" & integer'image(NUM_WORDS)
        severity failure;

      -- valida frame_done observado
      assert frame_done_seen = '1'
        report "ERRO: frame_done nao foi observado neste frame (pulso ausente)."
        severity failure;

      -- escreve resumo do frame no LOG
      write(L, string'("Frame ")); write(L, fr);
      write(L, string'(": sent_pixels=")); write(L, sent_pixels);
      write(L, string'("/")); write(L, TOTAL_PIXELS_IN);
      writeline(flog, L);

      write(L, string'("Frame ")); write(L, fr);
      write(L, string'(": got_words=")); write(L, got_words);
      write(L, string'("/")); write(L, NUM_WORDS);
      writeline(flog, L);

      write(L, string'("Frame ")); write(L, fr);
      write(L, string'(": frame_done_seen="));
      if frame_done_seen = '1' then
        write(L, string'("TRUE"));
      else
        write(L, string'("FALSE"));
      end if;
      writeline(flog, L);

      write(L, string'("Frame ")); write(L, fr);
      write(L, string'(": total_cycles=")); write(L, total_cycles);
      writeline(flog, L);

      write(L, string'("Frame ")); write(L, fr);
      write(L, string'(": END (OK)"));
      writeline(flog, L);

      write(L, string'("--------------------------------------------------"));
      writeline(flog, L);

      wait for 20*CLK_PERIOD;
    end loop;

    -- final
    write(L, string'("TESTE FINALIZADO: OK"));
    writeline(flog, L);
    file_close(flog);

    wait;
  end process;

end architecture;
