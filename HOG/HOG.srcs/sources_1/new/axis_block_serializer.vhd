library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use work.hogpack.all;

entity axis_block_serializer is
  port (
    clk : in  std_logic;
    rst : in  std_logic;

    frame_start : in std_logic;

    -- Entrada: descritor binário por bloco
    in_valid  : in  std_logic;
    in_ready  : out std_logic;
    desc_in   : in  std_logic_vector(HISTOGRAM_BITS_PER_BLOCK-1 downto 0);

    -- Saída AXI4-Stream (32-bit)
    m_axis_tdata  : out std_logic_vector(AXI_WORD_WIDTH-1 downto 0);
    m_axis_tvalid : out std_logic;
    m_axis_tready : in  std_logic;
    m_axis_tlast  : out std_logic;

    -- status
    frame_done : out std_logic
  );
end entity;

architecture rtl of axis_block_serializer is

  -- buffer do bloco atual
  signal buf_desc : std_logic_vector(HISTOGRAM_BITS_PER_BLOCK-1 downto 0) := (others => '0');
  signal buf_full : std_logic := '0';

  -- contadores
  signal word_in_block : integer range 0 to WORDS_PER_BLOCK-1 := 0;
  signal word_global   : integer range 0 to NUM_WORDS-1 := 0;

  -- controle de frame
  signal frame_active  : std_logic := '0';

  -- saída registrada
  signal tvalid_r : std_logic := '0';
  signal tdata_r  : std_logic_vector(AXI_WORD_WIDTH-1 downto 0) := (others => '0');
  signal tlast_r  : std_logic := '0';

  signal frame_done_r : std_logic := '0';

  -- handshake AXI
  signal fire : std_logic;

  -- pronto para aceitar novo bloco?
  signal in_ready_i : std_logic;

  -- helper: pega word i (32-bit) do descritor
  function get_word(
    d : std_logic_vector(HISTOGRAM_BITS_PER_BLOCK-1 downto 0);
    i : integer
  ) return std_logic_vector is
    variable w  : std_logic_vector(AXI_WORD_WIDTH-1 downto 0) := (others => '0');
    variable lo : integer;
  begin
    lo := i * AXI_WORD_WIDTH;
    for b in 0 to AXI_WORD_WIDTH-1 loop
      if (lo + b) <= (HISTOGRAM_BITS_PER_BLOCK-1) then
        w(b) := d(lo + b);
      else
        w(b) := '0';
      end if;
    end loop;
    return w;
  end function;

begin

  m_axis_tvalid <= tvalid_r;
  m_axis_tdata  <= tdata_r;
  m_axis_tlast  <= tlast_r;
  frame_done    <= frame_done_r;

  fire <= tvalid_r and m_axis_tready;

  -- Aceita novo bloco somente quando:
  -- - estamos em frame ativo
  -- - não há bloco sendo escoado (buf_full=0)
  -- - e não há beat pendente na saída (tvalid_r=0)
  -- Isso evita sobrescrita quando houver bolhas/backpressure.
  in_ready_i <= '1' when (frame_active='1' and buf_full='0' and tvalid_r='0') else '0';
  in_ready   <= in_ready_i;

  process(clk)
    variable next_data : std_logic_vector(AXI_WORD_WIDTH-1 downto 0);
    variable is_last   : boolean;
  begin
    if rising_edge(clk) then

      if rst = '1' then
        buf_desc      <= (others => '0');
        buf_full      <= '0';
        word_in_block <= 0;
        word_global   <= 0;
        frame_active  <= '0';

        tvalid_r      <= '0';
        tdata_r       <= (others => '0');
        tlast_r       <= '0';
        frame_done_r  <= '0';

      else
        frame_done_r <= '0';

        -- início de frame
        if frame_start = '1' then
          frame_active  <= '1';
          word_global   <= 0;
          word_in_block <= 0;
          buf_full      <= '0';

          tvalid_r <= '0';
          tlast_r  <= '0';
        end if;

        -- avanço AXI (somente quando realmente transmitiu)
        if fire = '1' then
          -- Calcula se o beat que ACABOU de sair era o último do frame
          is_last := (word_global = (NUM_WORDS - 1));

          -- Se foi o último, sinaliza frame_done e desativa frame.
          if is_last then
            frame_done_r <= '1';
            frame_active <= '0';
          end if;

          -- Avança word_global somente se não era o último (evita overflow / range)
          if not is_last then
            word_global <= word_global + 1;
          end if;

          -- Consome do bloco atual
          if buf_full = '1' then
            if word_in_block = (WORDS_PER_BLOCK - 1) then
              -- acabou o bloco
              buf_full      <= '0';
              word_in_block <= 0;
              tvalid_r      <= '0';
              tdata_r       <= (others => '0');
              tlast_r       <= '0';
            else
              -- próximo word do bloco
              word_in_block <= word_in_block + 1;
              next_data     := get_word(buf_desc, word_in_block + 1);

              -- TLAST do PRÓXIMO beat = 1 se o próximo word_global seria NUM_WORDS-1
              -- (como word_global só incrementa quando fire acontece, usamos o valor atual)
              if (word_global = (NUM_WORDS - 2)) then
                tlast_r <= '1';
              else
                tlast_r <= '0';
              end if;

              tdata_r  <= next_data;
              tvalid_r <= '1';
            end if;
          else
            -- não tem bloco: segura tvalid baixo
            tvalid_r <= '0';
            tdata_r  <= (others => '0');
            tlast_r  <= '0';
          end if;
        end if;

        -- captura novo bloco (somente quando pronto e sem beat pendente)
        if (in_valid = '1') and (in_ready_i = '1') then
          buf_desc      <= desc_in;
          buf_full      <= '1';
          word_in_block <= 0;

          tdata_r  <= get_word(desc_in, 0);
          tvalid_r <= '1';

          -- TLAST no PRIMEIRO beat do bloco se e somente se:
          -- word_global já está no último word do frame (NUM_WORDS-1)
          if word_global = (NUM_WORDS - 1) then
            tlast_r <= '1';
          else
            tlast_r <= '0';
          end if;
        end if;

      end if;
    end if;
  end process;

end architecture;
