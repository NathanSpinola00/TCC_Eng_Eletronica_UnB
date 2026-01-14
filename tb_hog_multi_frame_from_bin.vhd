library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.textio.all;
use ieee.std_logic_textio.all;

use work.hogpack.all;

entity tb_hog_multi_frame_from_bin is
end entity;

architecture sim of tb_hog_multi_frame_from_bin is
  constant CLK_PERIOD : time := 10 ns;

  -- ===========
  -- Pastas/nomes (iguais ao Python)
  -- ===========
  constant BASE_DIR : string := "C:\\Users\\Natan\\Documents\\Codigos_Python\\sim_inputs\\";
  constant N_FRAMES : integer := 20;

  -- ===========
  -- Clock/reset
  -- ===========
  signal clk : std_logic := '0';
  signal rst : std_logic := '1';
  signal frame_start : std_logic := '0';

  -- ==========================================================
  -- Sinais de entrada: pixels (1 byte por ciclo com handshake)
  -- ==========================================================
  signal s_valid : std_logic := '0';
  signal s_ready : std_logic := '0';
  signal s_pixel : unsigned(PIXEL_BITS-1 downto 0) := (others => '0');

  -- ==========================================================
  -- Sinais de saída: AXI-Stream 32-bit words (hog descriptor)
  -- ==========================================================
  signal m_valid : std_logic := '0';
  signal m_ready : std_logic := '1';
  signal m_data  : std_logic_vector(AXI_WORD_WIDTH-1 downto 0) := (others => '0');
  signal m_last  : std_logic := '0';

  -- (opcional) se seu top expõe frame_done
  signal frame_done : std_logic := '0';

  -- ===========
  -- Arquivos
  -- ===========
  file f_in  : text;
  file f_out : text;

  -- ===========
  -- Helpers
  -- ===========
  function frame_in_path(i : integer) return string is
    variable s : string(1 to 512);
    variable name : string(1 to 64);
  begin
    -- "frame_0000_pixels.txt"
    name := (others => ' ');
    -- monta via image com padding manual
    -- (VHDL não é lindo; use largura fixa)
    s := (others => ' ');
    return BASE_DIR & "frame_" &
           (if i < 10 then "000" elsif i < 100 then "00" elsif i < 1000 then "0" else "" end if) &
           integer'image(i) & "_pixels.txt";
  end function;

  function frame_out_path(i : integer) return string is
  begin
    return BASE_DIR & "frame_" &
           (if i < 10 then "000" elsif i < 100 then "00" elsif i < 1000 then "0" else "" end if) &
           integer'image(i) & "_hog_out.txt";
  end function;

begin
  -- clock
  clk <= not clk after CLK_PERIOD/2;

  -------------------------------------------------------------------------
  -- ================================================================
  -- ADAPTE AQUI: instancie o seu TOP que já gera hog_out via AXI-Stream
  --
  -- Você precisa ligar:
  --   clk, rst, frame_start
  --   entrada pixel (valid/ready + pixel)
  --   saída AXI (valid/ready + data + last)
  --
  -- Substitua "top_hog_axi" e os nomes de ports conforme o seu projeto.
  -- ================================================================
  -------------------------------------------------------------------------

  -- EXEMPLO (AJUSTE):
  -- U_DUT: entity work.top_hog_axi
  --   port map (
  --     clk         => clk,
  --     rst         => rst,
  --     frame_start => frame_start,
  --
  --     in_valid    => s_valid,
  --     in_ready    => s_ready,
  --     pixel_in    => s_pixel,
  --
  --     m_axis_tvalid => m_valid,
  --     m_axis_tready => m_ready,
  --     m_axis_tdata  => m_data,
  --     m_axis_tlast  => m_last,
  --
  --     frame_done    => frame_done
  --   );

  -------------------------------------------------------------------------
  -- TB main
  -------------------------------------------------------------------------
  p_main: process
    variable L : line;
    variable Lin : line;
    variable Lout : line;

    variable slv8 : std_logic_vector(PIXEL_BITS-1 downto 0);

    variable i_frame : integer;
    variable sent_pixels : integer;
    variable got_words   : integer;

    variable holding : boolean;

    -- strings de path
    variable in_path  : string(1 to 512);
    variable out_path : string(1 to 512);

  begin
    -- init
    s_valid <= '0';
    s_pixel <= (others => '0');
    m_ready <= '1';

    -- reset
    rst <= '1';
    frame_start <= '0';
    wait for 10*CLK_PERIOD;
    wait until rising_edge(clk);
    rst <= '0';

    -- loop frames
    for i_frame in 0 to N_FRAMES-1 loop
      -- abre arquivos
      -- (paths fixos)
      in_path  := (others => ' ');
      out_path := (others => ' ');
      -- como não dá pra atribuir string variável facilmente, usamos direto no file_open abaixo

      file_open(f_in,  BASE_DIR & "frame_" &
                      (if i_frame < 10 then "000" elsif i_frame < 100 then "00" elsif i_frame < 1000 then "0" else "" end if) &
                      integer'image(i_frame) & "_pixels.txt", read_mode);

      file_open(f_out, BASE_DIR & "frame_" &
                      (if i_frame < 10 then "000" elsif i_frame < 100 then "00" elsif i_frame < 1000 then "0" else "" end if) &
                      integer'image(i_frame) & "_hog_out.txt", write_mode);

      -- header
      write(Lout, string'("last_i HEXDATA"));
      writeline(f_out, Lout);

      -- pulso frame_start
      wait until rising_edge(clk);
      frame_start <= '1';
      wait until rising_edge(clk);
      frame_start <= '0';

      -- ============================
      -- Envia 34x34 = TOTAL_PIXELS_IN pixels
      -- lendo BINÁRIO (8 bits) por linha
      -- handshake correto (sem U/X)
      -- ============================
      sent_pixels := 0;
      holding := false;
      s_valid <= '0';
      s_pixel <= (others => '0');

      while sent_pixels < TOTAL_PIXELS_IN loop
        wait until rising_edge(clk);

        -- carrega novo pixel só quando não está segurando
        if (not holding) then
          if endfile(f_in) then
            assert false report "pixels.txt acabou antes de TOTAL_PIXELS_IN" severity failure;
          end if;

          readline(f_in, Lin);
          slv8 := (others => '0');
          read(Lin, slv8);         -- lê "00101110"
          s_pixel <= unsigned(slv8);
          s_valid <= '1';
          holding := true;
        end if;

        -- handshake
        if (s_valid='1') and (s_ready='1') then
          sent_pixels := sent_pixels + 1;
          holding := false;
          s_valid <= '0';  -- vai carregar o próximo no próximo ciclo
        end if;
      end loop;

      -- encerra envio
      wait until rising_edge(clk);
      s_valid <= '0';
      s_pixel <= (others => '0');
      file_close(f_in);

      -- ============================
      -- Captura saída: NUM_WORDS words
      -- ============================
      got_words := 0;
      while got_words < NUM_WORDS loop
        wait until rising_edge(clk);

        if (m_valid='1') and (m_ready='1') then
          write(Lout, got_words);
          write(Lout, string'(" "));
          hwrite(Lout, m_data);
          writeline(f_out, Lout);

          got_words := got_words + 1;
        end if;
      end loop;

      file_close(f_out);

      report "FRAME " & integer'image(i_frame) &
             " sent_pixels=" & integer'image(sent_pixels) &
             " got_words=" & integer'image(got_words) severity note;

      -- pequena folga
      wait for 10*CLK_PERIOD;
    end loop;

    report "DONE ALL FRAMES" severity note;
    wait;
  end process;

end architecture;
