library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use work.hogpack.all;

entity win_cross_taps is
  port (
    clk : in std_logic;
    rst : in std_logic;

    frame_start : in std_logic;

    -- stream in
    in_valid : in  std_logic;
    in_ready : out std_logic;
    pixel_in : in  unsigned(PIXEL_BITS-1 downto 0);

    -- stream out (taps)
    out_valid : out std_logic;
    out_ready : in  std_logic;

    p12 : out unsigned(PIXEL_BITS-1 downto 0); -- up
    p21 : out unsigned(PIXEL_BITS-1 downto 0); -- left
    p23 : out unsigned(PIXEL_BITS-1 downto 0); -- right
    p32 : out unsigned(PIXEL_BITS-1 downto 0)  -- down
  );
end entity;

architecture rtl of win_cross_taps is
  type line_t is array (0 to PAD_SIZE-1) of unsigned(PIXEL_BITS-1 downto 0);
  signal line1, line2 : line_t := (others => (others => '0'));

  signal x : integer range 0 to PAD_SIZE-1 := 0;
  signal y : integer range 0 to PAD_SIZE-1 := 0;

  -- shift regs horizontais (3 colunas) para: linha y-2 (a*), linha y-1 (b*), linha y (c*)
  signal a0,a1,a2 : unsigned(PIXEL_BITS-1 downto 0) := (others=>'0');
  signal b0,b1,b2 : unsigned(PIXEL_BITS-1 downto 0) := (others=>'0');
  signal c0,c1,c2 : unsigned(PIXEL_BITS-1 downto 0) := (others=>'0');

  -- 1-deep buffer de saída (taps)
  signal v : std_logic := '0';  -- out_valid reg

  signal p12_r, p21_r, p23_r, p32_r : unsigned(PIXEL_BITS-1 downto 0) := (others=>'0');

  signal can_accept : std_logic;
  signal fire_in    : std_logic;

begin
  -- posso aceitar novo pixel se:
  -- - não tenho saída pendente (v=0), ou
  -- - tenho saída pendente mas ela será consumida agora (out_ready=1)
  can_accept <= '1' when (v='0') or (out_ready='1') else '0';

  in_ready  <= can_accept;
  fire_in   <= in_valid and can_accept;

  out_valid <= v;

  p12 <= p12_r;  p21 <= p21_r;  p23 <= p23_r;  p32 <= p32_r;

  process(clk)
    variable pix_up2, pix_up1, pix_cur : unsigned(PIXEL_BITS-1 downto 0);
    variable win_valid_now : std_logic;
    variable x_next, y_next : integer;
  begin
    if rising_edge(clk) then
      if rst='1' then
        v <= '0';
        x <= 0; y <= 0;

        a0 <= (others=>'0'); a1 <= (others=>'0'); a2 <= (others=>'0');
        b0 <= (others=>'0'); b1 <= (others=>'0'); b2 <= (others=>'0');
        c0 <= (others=>'0'); c1 <= (others=>'0'); c2 <= (others=>'0');

        p12_r <= (others=>'0'); p21_r <= (others=>'0'); p23_r <= (others=>'0'); p32_r <= (others=>'0');

        line1 <= (others => (others => '0'));
        line2 <= (others => (others => '0'));

      else
        if frame_start='1' then
          v <= '0';
          x <= 0; y <= 0;

          a0 <= (others=>'0'); a1 <= (others=>'0'); a2 <= (others=>'0');
          b0 <= (others=>'0'); b1 <= (others=>'0'); b2 <= (others=>'0');
          c0 <= (others=>'0'); c1 <= (others=>'0'); c2 <= (others=>'0');

          p12_r <= (others=>'0'); p21_r <= (others=>'0'); p23_r <= (others=>'0'); p32_r <= (others=>'0');

          line1 <= (others => (others => '0'));
          line2 <= (others => (others => '0'));

        else
          -- consumo da saída pendente
          if (v='1') and (out_ready='1') then
            v <= '0';
          end if;

          -- só avança estado se o pixel foi realmente aceito (fire_in)
          if fire_in='1' then
            -- janela é válida considerando o (x,y) atual (antes de avançar)
            if (x >= 2) and (y >= 2) then
              win_valid_now := '1';
            else
              win_valid_now := '0';
            end if;

            pix_up1 := line1(x);
            pix_up2 := line2(x);
            pix_cur := pixel_in;

            -- shift horizontal
            a0 <= a1; a1 <= a2; a2 <= pix_up2;
            b0 <= b1; b1 <= b2; b2 <= pix_up1;
            c0 <= c1; c1 <= c2; c2 <= pix_cur;

            -- atualiza line buffers
            line2(x) <= line1(x);
            line1(x) <= pix_cur;

            -- taps do centro b1 (linha y-1, col x-1) após o shift:
            -- up=a1, left=b0, right=b2, down=c1
            p12_r <= a1;
            p21_r <= b0;
            p23_r <= b2;
            p32_r <= c1;

            -- gera out_valid somente quando a janela existe
            if win_valid_now='1' then
              v <= '1';
            end if;

            -- avança posição (x,y) no frame padded
            if x = PAD_SIZE-1 then
              x_next := 0;
              if y = PAD_SIZE-1 then
                y_next := 0;
              else
                y_next := y + 1;
              end if;
            else
              x_next := x + 1;
              y_next := y;
            end if;

            x <= x_next;
            y <= y_next;
          end if; -- fire_in
        end if; -- frame_start
      end if; -- rst
    end if; -- rising_edge
  end process;

end architecture;
