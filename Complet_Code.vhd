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

 ----------------------------------------------------------------------------------
-- Arquivo: grad_mag_bin.vhd  (VERSÃO TAN/LUT - Proposta 3 / TCC)
-- Descricao:
--   Bloco combinado (1 token) para Proposta 3:
--     - Gradientes: gx = p23 - p21, gy = p32 - p12  (somente subtrações)
--     - Magnitude aproximada:
--         a=max(|gx|,|gy|), b=min(...)
--         mag = max(0.875*a + 0.5*b, a)
--     - Orientação (bin 0..8) SEM atan:
--         usa LUT de tangentes e comparações por multiplicação:
--           |gy| * TAN_SCALE  vs  |gx| * TAN_theta
--         com regras por quadrante (0..180) conforme Proposta/TCC.
--
--   Interface stall-capable (valid/ready): mag e bin sincronizados.
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use work.hogpack.all;

entity grad_mag_bin is
  port (
    clk : in  std_logic;
    rst : in  std_logic;

    -- Handshake de entrada (taps em cruz do win_cross_taps)
    in_valid : in  std_logic;
    in_ready : out std_logic;

    p12 : in unsigned(PIXEL_BITS-1 downto 0); -- up
    p21 : in unsigned(PIXEL_BITS-1 downto 0); -- left
    p23 : in unsigned(PIXEL_BITS-1 downto 0); -- right
    p32 : in unsigned(PIXEL_BITS-1 downto 0); -- down

    -- Handshake de saída (token sincronizado)
    out_valid : out std_logic;
    out_ready : in  std_logic;

    mag_out : out unsigned(MAG_BITS-1 downto 0);
    bin_out : out unsigned(3 downto 0)        -- 0..8
  );
end entity;

architecture rtl of grad_mag_bin is
  ------------------------------------------------------------------------------
  -- 1-deep buffer (segura a saída quando out_ready=0)
  ------------------------------------------------------------------------------
  signal v_out       : std_logic := '0';
  signal in_ready_i  : std_logic := '0';

  -- Registradores de saída (token)
  signal mag_r : unsigned(MAG_BITS-1 downto 0) := (others => '0');
  signal bin_r : unsigned(3 downto 0)          := (others => '0');

begin
  -- stall-capable: aceita novo token se não há token pendente
  -- ou se o token pendente será consumido agora
  in_ready_i <= '1' when (v_out = '0') or (out_ready = '1') else '0';

  in_ready  <= in_ready_i;
  out_valid <= v_out;

  mag_out <= mag_r;
  bin_out <= bin_r;

  process(clk)
    -- Gradientes e absolutos
    variable gx_s, gy_s     : signed(GRAD_BITS-1 downto 0);
    variable abs_gx, abs_gy : unsigned(GRAD_BITS-1 downto 0);

    -- magnitude
    variable a, b     : unsigned(GRAD_BITS-1 downto 0);
    variable t1, t2   : unsigned(GRAD_BITS downto 0);
    variable approx   : unsigned(GRAD_BITS downto 0);
    variable a_ext    : unsigned(GRAD_BITS downto 0);
    variable mag_tmp  : unsigned(MAG_BITS-1 downto 0);

    -- bin
    variable bin_var  : unsigned(3 downto 0);

    -- flags de sinal
    variable gx_neg, gy_neg : std_logic;

    -- Comparações TAN/LUT via cross-multiply:
    --   lhs = |gy|*TAN_SCALE
    --   rhs = |gx|*TAN_x
    --
    -- Para evitar ambiguidade de largura no "*", usamos produtos explícitos.
    constant MULW_LHS  : integer := GRAD_BITS + TAN_SCALE_BITS;
    constant MULW_RHS  : integer := GRAD_BITS + TAN_SCALE_BITS;

    variable gx_ext    : unsigned(GRAD_BITS-1 downto 0);
    variable gy_ext    : unsigned(GRAD_BITS-1 downto 0);

    variable prod_lhs  : unsigned(MULW_LHS-1 downto 0);
    variable rhs20     : unsigned(MULW_RHS-1 downto 0);
    variable rhs40     : unsigned(MULW_RHS-1 downto 0);
    variable rhs60     : unsigned(MULW_RHS-1 downto 0);
    variable rhs80     : unsigned(MULW_RHS-1 downto 0);

  begin
    if rising_edge(clk) then
      if rst='1' then
        v_out <= '0';
        mag_r <= (others => '0');
        bin_r <= (others => '0');

      else
        if in_ready_i='1' then
          v_out <= '0'; -- default: sem token, sem valid

          if in_valid='1' then
            -- =========================================================
            -- 1) GRADIENTES
            -- =========================================================
            gx_s := resize(signed('0' & p23), GRAD_BITS) - resize(signed('0' & p21), GRAD_BITS);
            gy_s := resize(signed('0' & p32), GRAD_BITS) - resize(signed('0' & p12), GRAD_BITS);

            gx_neg := gx_s(gx_s'high);
            gy_neg := gy_s(gy_s'high);

            -- abs
            if gx_neg='1' then abs_gx := unsigned(-gx_s); else abs_gx := unsigned(gx_s); end if;
            if gy_neg='1' then abs_gy := unsigned(-gy_s); else abs_gy := unsigned(gy_s); end if;

            -- =========================================================
            -- 2) MAGNITUDE APROX
            -- =========================================================
            if abs_gx >= abs_gy then
              a := abs_gx;
              b := abs_gy;
            else
              a := abs_gy;
              b := abs_gx;
            end if;

            t1     := ('0' & a) - (('0' & a) srl 3); -- 0.875*a
            t2     := (('0' & b) srl 1);             -- 0.5*b
            approx := t1 + t2;

            a_ext := ('0' & a);

            if approx > a_ext then
              mag_tmp := resize(approx, MAG_BITS);
            else
              mag_tmp := resize(a_ext, MAG_BITS);
            end if;

            -- =========================================================
            -- 3) ORIENTAÇÃO (TAN/LUT)
            --
            -- 9 bins uniformes em 0..180:
            --   0: ~0°    ... 4: ~90° ... 8: ~180°(=0°)
            --
            -- Decide "faixa" pelo |gy|/|gx| usando thresholds tan(20,40,60,80).
            -- =========================================================
            bin_var := to_unsigned(0,4);

            gx_ext := abs_gx;
            gy_ext := abs_gy;

            -- produtos (cross-multiply) com largura correta:
            -- (GRAD_BITS) * (TAN_SCALE_BITS) => (GRAD_BITS+TAN_SCALE_BITS) = MULW
            prod_lhs := resize(abs_gy, GRAD_BITS) * resize(TAN_SCALE, TAN_SCALE_BITS);
            rhs20    := resize(abs_gx, GRAD_BITS) * resize(TAN_20,  TAN_SCALE_BITS);
            rhs40    := resize(abs_gx, GRAD_BITS) * resize(TAN_40,  TAN_SCALE_BITS);
            rhs60    := resize(abs_gx, GRAD_BITS) * resize(TAN_60,  TAN_SCALE_BITS);
            rhs80    := resize(abs_gx, GRAD_BITS) * resize(TAN_80,  TAN_SCALE_BITS);


            -- Se gx=0, define como 90° (bin 4) (evita divisão por zero conceitual)
            if abs_gx = 0 then
              bin_var := to_unsigned(4,4);
            else
              -- faixa 0..4 pela inclinação em [0..90]
              -- r < tan20 => 0, <tan40 =>1, <tan60=>2, <tan80=>3, else =>4
              if    prod_lhs < rhs20 then bin_var := to_unsigned(0,4);
              elsif prod_lhs < rhs40 then bin_var := to_unsigned(1,4);
              elsif prod_lhs < rhs60 then bin_var := to_unsigned(2,4);
              elsif prod_lhs < rhs80 then bin_var := to_unsigned(3,4);
              else                         bin_var := to_unsigned(4,4);
              end if;

              -- mapeia quadrantes para 0..180 (0..8)
              -- Mantém simetria conforme seu "angulo.vhd" base:
              -- QI  (gx>=0, gy>=0): 0..4
              -- QII (gx< 0, gy>=0): 8..4 (espelhado)
              -- QIII(gx< 0, gy< 0): 0..4
              -- QIV (gx>=0, gy< 0): 8..4 (espelhado)
              if (gx_neg='0' and gy_neg='0') then
                -- QI: já está 0..4
                null;

              elsif (gx_neg='1' and gy_neg='0') then
                -- QII: 0->8,1->7,2->6,3->5,4->4
                case to_integer(bin_var) is
                  when 0 => bin_var := to_unsigned(8,4);
                  when 1 => bin_var := to_unsigned(7,4);
                  when 2 => bin_var := to_unsigned(6,4);
                  when 3 => bin_var := to_unsigned(5,4);
                  when others => bin_var := to_unsigned(4,4);
                end case;

              elsif (gx_neg='1' and gy_neg='1') then
                -- QIII: volta para 0..4 (mesma tabela)
                null;

              else
                -- QIV (gx>=0, gy<0): 0->8,1->7,2->6,3->5,4->4
                case to_integer(bin_var) is
                  when 0 => bin_var := to_unsigned(8,4);
                  when 1 => bin_var := to_unsigned(7,4);
                  when 2 => bin_var := to_unsigned(6,4);
                  when 3 => bin_var := to_unsigned(5,4);
                  when others => bin_var := to_unsigned(4,4);
                end case;
              end if;
            end if;

            -- =========================================================
            -- Saída (1 token)
            -- =========================================================
            mag_r <= mag_tmp;
            bin_r <= bin_var;
            v_out <= '1';
          end if;
        end if; -- in_ready_i
      end if; -- rst
    end if; -- clk
  end process;

end architecture;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use work.hogpack.all;

entity hog_cell_histogram is
  port (
    clk : in  std_logic;
    rst : in  std_logic;

    frame_start : in std_logic;

    -- Entrada: 1 token por pixel útil (ROI_SIZE x ROI_SIZE)
    in_valid : in  std_logic;
    in_ready : out std_logic;
    mag_in   : in  unsigned(MAG_BITS-1 downto 0);
    bin_in   : in  unsigned(3 downto 0); -- 0..8

    -- Saída: 1 token por célula
    out_valid     : out std_logic;
    out_ready     : in  std_logic;
    cell_idx_out  : out unsigned(NUM_CELLS_BITS-1 downto 0);
    cell_hist_out : out CellHist_t
  );
end entity;

architecture rtl of hog_cell_histogram is
  -- pixel counters
  signal x : integer range 0 to ROI_SIZE-1 := 0;
  signal y : integer range 0 to ROI_SIZE-1 := 0;

  -- acumuladores internos
  type ucell_t is array(0 to NUM_BINS-1) of unsigned(HIST_BIN_BITS-1 downto 0);
  signal acc : ucell_t := (others => (others => '0'));

  -- 1-deep output buffer (token de célula)
  signal v_out : std_logic := '0';
  signal cell_idx_r : unsigned(NUM_CELLS_BITS-1 downto 0) := (others => '0');
  signal cell_hist_r : CellHist_t := (others => (others => '0'));

  signal in_ready_i : std_logic;
  signal take_in    : std_logic;

  function clamp_bin(b : unsigned(3 downto 0)) return integer is
    variable bi : integer;
  begin
    bi := to_integer(b);
    if bi < 0 then return 0;
    elsif bi > (NUM_BINS-1) then return (NUM_BINS-1);
    else return bi;
    end if;
  end function;

begin
  -- trava entrada enquanto houver célula pendente para o downstream
  in_ready_i <= '1' when (v_out='0') else '0';
  in_ready   <= in_ready_i;
  take_in    <= in_valid and in_ready_i;

  out_valid    <= v_out;
  cell_idx_out <= cell_idx_r;
  cell_hist_out<= cell_hist_r;

  process(clk)
    variable acc_next : ucell_t;
    variable bin_i    : integer;
    variable mag_ext  : unsigned(HIST_BIN_BITS-1 downto 0);

    variable cx, cy   : integer;
    variable cell_idx : integer;
    variable end_cell : boolean;

    variable x_next, y_next : integer;
    variable out_hist : CellHist_t;
  begin
    if rising_edge(clk) then
      if rst='1' then
        x <= 0; y <= 0;
        acc <= (others => (others => '0'));
        v_out <= '0';
        cell_idx_r <= (others => '0');
        cell_hist_r <= (others => (others => '0'));
      else
        if frame_start='1' then
          x <= 0; y <= 0;
          acc <= (others => (others => '0'));
          v_out <= '0';
          cell_idx_r <= (others => '0');
          cell_hist_r <= (others => (others => '0'));
        else
          -- consumo do token de célula
          if (v_out='1') and (out_ready='1') then
            v_out <= '0';
          end if;

          -- processa pixel (somente se não há saída pendente)
          if take_in='1' then
            acc_next := acc;

            bin_i   := clamp_bin(bin_in);
            mag_ext := resize(mag_in, HIST_BIN_BITS);
            acc_next(bin_i) := acc_next(bin_i) + mag_ext;

            end_cell := ((x mod CELL_SIZE) = (CELL_SIZE-1)) and
                        ((y mod CELL_SIZE) = (CELL_SIZE-1));

            -- próximo pixel
            if x = ROI_SIZE-1 then
              x_next := 0;
              if y = ROI_SIZE-1 then y_next := 0;
              else                   y_next := y + 1;
              end if;
            else
              x_next := x + 1;
              y_next := y;
            end if;

            x <= x_next;
            y <= y_next;

            if end_cell then
              cx := x / CELL_SIZE;
              cy := y / CELL_SIZE;
              cell_idx := cy * NUM_CELLS_X + cx;

              -- converte ucell_t -> CellHist_t
              for i in 0 to NUM_BINS-1 loop
                out_hist(i) := resize(acc_next(i), HIST_BIN_BITS);
              end loop;

              cell_idx_r  <= to_unsigned(cell_idx, NUM_CELLS_BITS);
              cell_hist_r <= out_hist;
              v_out       <= '1';

              acc <= (others => (others => '0'));
            else
              acc <= acc_next;
            end if;
          end if;
        end if;
      end if;
    end if;
  end process;

end architecture;  

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use work.hogpack.all;

entity hog_block_assemble is
  port (
    clk : in  std_logic;
    rst : in  std_logic;

    frame_start : in std_logic;

    -- Entrada: 1 token por célula
    in_valid     : in  std_logic;
    in_ready     : out std_logic;
    cell_idx_in  : in  unsigned(NUM_CELLS_BITS-1 downto 0);
    cell_hist_in : in  CellHist_t;

    -- Saída: 1 token por bloco
    out_valid      : out std_logic;
    out_ready      : in  std_logic;
    block_hist_out : out BlockHist_t
  );
end entity;

architecture rtl of hog_block_assemble is

  constant K       : integer := BLOCK_SIDE;
  constant LB_ROWS : integer := K-1;

  type lb_row_t is array (0 to NUM_CELLS_X-1) of CellHist_t;
  type lb_mem_t is array (0 to LB_ROWS-1) of lb_row_t;

  signal lb_mem : lb_mem_t := (others => (others => (others => (others => '0'))));
  signal cur_row : lb_row_t := (others => (others => (others => '0')));

  signal v_out        : std_logic := '0';
  signal block_hist_r : BlockHist_t := (others => (others => (others => '0')));

  signal in_ready_i : std_logic;
  signal block_cnt : unsigned(BLOCK_COUNTER_BITS-1 downto 0) := (others => '0');

  function mod_pos(a : integer; m : integer) return integer is
    variable r : integer;
  begin
    if m <= 0 then return 0; end if;
    r := a mod m;
    if r < 0 then r := r + m; end if;
    return r;
  end function;

begin
  in_ready_i <= '1' when (v_out='0') or (out_ready='1') else '0';
  in_ready   <= in_ready_i;

  out_valid      <= v_out;
  block_hist_out <= block_hist_r;

  process(clk)
    variable idx_i : integer;
    variable cx, cy : integer;

    variable row_slot_write : integer;
    variable slot_read      : integer;

    variable new_block : BlockHist_t;
    variable by, bx    : integer;
    variable cell_lin  : integer;

    variable write_lb_now : boolean;
    variable cur_row_next : lb_row_t;
  begin
    if rising_edge(clk) then
      if rst='1' then
        v_out        <= '0';
        block_hist_r <= (others => (others => (others => '0')));
        block_cnt    <= (others => '0');
        lb_mem       <= (others => (others => (others => (others => '0'))));
        cur_row      <= (others => (others => (others => '0')));

      elsif frame_start='1' then
        v_out        <= '0';
        block_hist_r <= (others => (others => (others => '0')));
        block_cnt    <= (others => '0');
        lb_mem       <= (others => (others => (others => (others => '0'))));
        cur_row      <= (others => (others => (others => '0')));

      else
        if (v_out='1') and (out_ready='1') then
          v_out <= '0';
        end if;

        if (in_valid='1') and (in_ready_i='1') then
          idx_i := to_integer(cell_idx_in);
          cx := idx_i mod NUM_CELLS_X;
          cy := idx_i / NUM_CELLS_X;

          -- prepara linha atual "next"
          cur_row_next := cur_row;
          cur_row_next(cx) := cell_hist_in;

          -- registra linha atual
          cur_row <= cur_row_next;

          -- fim da linha?
          write_lb_now := (LB_ROWS > 0) and (cx = (NUM_CELLS_X-1));

          -- (A) PRIMEIRO monta bloco usando lb_mem ANTIGO (linha cy-1 preservada)
          if (cx >= (K-1)) and (cy >= (K-1)) and
             (to_integer(block_cnt) < TOTAL_BLOCKS) then

            for by in 0 to K-1 loop
              for bx in 0 to K-1 loop
                cell_lin := by*K + bx;

                if by = K-1 then
                  new_block(cell_lin) := cur_row_next(cx - (K-1-bx));
                else
                  slot_read := mod_pos(cy - (K-1-by), LB_ROWS);
                  new_block(cell_lin) := lb_mem(slot_read)(cx - (K-1-bx));
                end if;

              end loop;
            end loop;

            block_hist_r <= new_block;
            v_out        <= '1';
            block_cnt    <= block_cnt + 1;
          end if;

          -- (B) DEPOIS, se acabou a linha, empurra cur_row_next para lb_mem
          if write_lb_now then
            row_slot_write := mod_pos(cy, LB_ROWS);
            lb_mem(row_slot_write) <= cur_row_next;
          end if;

          -- limpa cur_row no fim da linha (opcional)
          if cx = (NUM_CELLS_X-1) then
            cur_row <= (others => (others => (others => '0')));
          end if;

        end if;
      end if;
    end if;
  end process;

end architecture;

----------------------------------------------------------------------------------
-- Arquivo: block_binarize_v3.vhd
-- Proposta 3 (Legarda) - binarização por bloco:
--   - Entrada: BlockHist_t (BLOCK_SIZE células, cada uma com NUM_BINS bins amplitude)
--   - Soma total do bloco (todos os bins) => soma_total
--   - Média: avg = soma_total / (BLOCK_SIZE*NUM_BINS)
--   - Saída binária: bit_i = 1 se bin_i >= avg, senão 0
--
-- Stall-capable: 1-deep buffer na saída.
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

use work.hogpack.all;

entity block_binarize_v3 is
  port (
    clk : in  std_logic;
    rst : in  std_logic;

    frame_start : in std_logic;

    -- Entrada: token por bloco
    in_valid      : in  std_logic;
    in_ready      : out std_logic;
    block_hist_in : in  BlockHist_t;

    -- Saída: descritor binário do bloco
    out_valid       : out std_logic;
    out_ready       : in  std_logic;
    bin_desc_out    : out std_logic_vector(HISTOGRAM_BITS_PER_BLOCK-1 downto 0)
  );
end entity;

architecture rtl of block_binarize_v3 is
  constant NUM_FEATURES : integer := BLOCK_SIZE * NUM_BINS;

  -- 1-deep output buffer
  signal v_out   : std_logic := '0';
  signal desc_r  : std_logic_vector(HISTOGRAM_BITS_PER_BLOCK-1 downto 0) := (others => '0');

  signal in_ready_i : std_logic;

begin
  -- posso aceitar novo bloco se:
  -- - não tenho saída pendente, ou
  -- - tenho saída pendente mas o downstream vai consumir agora
  in_ready_i <= '1' when (v_out='0') or (out_ready='1') else '0';
  in_ready   <= in_ready_i;

  out_valid    <= v_out;
  bin_desc_out <= desc_r;

  process(clk)
    variable sum_total : unsigned(SUM_BLOCK_BITS-1 downto 0);
    variable avg       : unsigned(HIST_BIN_BITS-1 downto 0);

    variable bitvec : std_logic_vector(HISTOGRAM_BITS_PER_BLOCK-1 downto 0);
    variable k      : integer;

    variable val_bin : unsigned(HIST_BIN_BITS-1 downto 0);
  begin
    if rising_edge(clk) then
      if rst='1' then
        v_out  <= '0';
        desc_r <= (others => '0');

      else
        if frame_start='1' then
          v_out  <= '0';
          desc_r <= (others => '0');

        else
          -- consumo de saída
          if (v_out='1') and (out_ready='1') then
            v_out <= '0';
          end if;

          -- calcula novo descritor se aceitar entrada
          if (in_valid='1') and (in_ready_i='1') then
            -- 1) soma total (todos os bins do bloco)
            sum_total := (others => '0');
            for c in 0 to BLOCK_SIZE-1 loop
              for b in 0 to NUM_BINS-1 loop
                sum_total := sum_total + resize(block_hist_in(c)(b), SUM_BLOCK_BITS);
              end loop;
            end loop;

            -- 2) média por feature
            -- avg tem HIST_BIN_BITS, sum_total é maior: divide por constante
            avg := resize(sum_total / to_unsigned(NUM_FEATURES, SUM_BLOCK_BITS), HIST_BIN_BITS);

            -- 3) binariza em ordem linear: cell-major, depois bin
            -- idx = c*NUM_BINS + b
            bitvec := (others => '0');
            for c in 0 to BLOCK_SIZE-1 loop
              for b in 0 to NUM_BINS-1 loop
                k := c*NUM_BINS + b;
                val_bin := block_hist_in(c)(b);
                if val_bin >= avg then
                  bitvec(k) := '1';
                else
                  bitvec(k) := '0';
                end if;
              end loop;
            end loop;

            desc_r <= bitvec;
            v_out  <= '1';
          end if;

        end if;
      end if;
    end if;
  end process;

end architecture;

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
      out_ready      => bin_in_ready,     
      block_hist_out => blk_hist
    );

  -- binarize
  U_BIN : entity work.block_binarize_v3
    port map (
      clk => clk,
      rst => rst,
      frame_start => frame_start,

      in_valid      => blk_valid,
      in_ready      => bin_in_ready,   
      block_hist_in => blk_hist,

      out_valid    => bin_valid,
      out_ready    => bin_out_ready,      
      bin_desc_out => bin_desc
    );

  -- serializer
  U_SER : entity work.axis_block_serializer
    port map (
      clk => clk,
      rst => rst,
      frame_start => frame_start,

      in_valid => bin_valid,
      in_ready => bin_out_ready,          
      desc_in  => bin_desc,

      m_axis_tdata  => m_axis_tdata,
      m_axis_tvalid => m_axis_tvalid,
      m_axis_tready => m_axis_tready,
      m_axis_tlast  => m_axis_tlast,

      frame_done => frame_done
    );

end architecture;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.hogpack.all;

entity hog_ip_axi_Nathan is
  generic (
    C_S_AXI_ADDR_WIDTH : integer := 8;
    C_S_AXI_DATA_WIDTH : integer := 32
  );
  port (
    aclk    : in  std_logic;
    aresetn : in  std_logic;

    -- AXI4-Stream Slave (pixels)
    s_axis_tdata  : in  std_logic_vector(PIXEL_BITS-1 downto 0);
    s_axis_tvalid : in  std_logic;
    s_axis_tready : out std_logic;
    s_axis_tlast  : in  std_logic;

    -- AXI4-Stream Master (descritor)
    m_axis_tdata  : out std_logic_vector(AXI_WORD_WIDTH-1 downto 0);
    m_axis_tvalid : out std_logic;
    m_axis_tready : in  std_logic;
    m_axis_tlast  : out std_logic;

    -- AXI4-Lite Slave
    s_axi_awaddr  : in  std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
    s_axi_awvalid : in  std_logic;
    s_axi_awready : out std_logic;

    s_axi_wdata   : in  std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
    s_axi_wstrb   : in  std_logic_vector((C_S_AXI_DATA_WIDTH/8)-1 downto 0);
    s_axi_wvalid  : in  std_logic;
    s_axi_wready  : out std_logic;

    s_axi_bresp   : out std_logic_vector(1 downto 0);
    s_axi_bvalid  : out std_logic;
    s_axi_bready  : in  std_logic;

    s_axi_araddr  : in  std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
    s_axi_arvalid : in  std_logic;
    s_axi_arready : out std_logic;

    s_axi_rdata   : out std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
    s_axi_rresp   : out std_logic_vector(1 downto 0);
    s_axi_rvalid  : out std_logic;
    s_axi_rready  : in  std_logic
  );
end entity;

architecture rtl of hog_ip_axi_Nathan is

  signal rst : std_logic;

  -- Internos p/ não ler OUT
  signal s_axis_tready_i : std_logic := '0';

  signal m_axis_tdata_i  : std_logic_vector(AXI_WORD_WIDTH-1 downto 0);
  signal m_axis_tvalid_i : std_logic;
  signal m_axis_tlast_i  : std_logic;

  signal s_axi_awready_i : std_logic := '0';
  signal s_axi_wready_i  : std_logic := '0';
  signal s_axi_arready_i : std_logic := '0';

  signal s_axi_bresp_i   : std_logic_vector(1 downto 0) := "00";
  signal s_axi_bvalid_i  : std_logic := '0';

  signal s_axi_rdata_i   : std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0) := (others => '0');
  signal s_axi_rresp_i   : std_logic_vector(1 downto 0) := "00";
  signal s_axi_rvalid_i  : std_logic := '0';

  -- Core
  signal frame_start : std_logic := '0';
  signal in_valid    : std_logic := '0';
  signal in_ready    : std_logic;
  signal pixel_in    : unsigned(PIXEL_BITS-1 downto 0);
  signal frame_done_core : std_logic;

  -- Estado
  signal in_frame : std_logic := '0';

  signal pix_cnt        : unsigned(31 downto 0) := (others => '0');
  signal word_cnt       : unsigned(31 downto 0) := (others => '0');
  signal pix_cnt_last   : unsigned(31 downto 0) := (others => '0');
  signal word_cnt_last  : unsigned(31 downto 0) := (others => '0');

  signal busy_latched        : std_logic := '0';
  signal frame_done_latched  : std_logic := '0';
  signal error_latched       : std_logic := '0';

  signal tlast_in_early      : std_logic := '0';
  signal tlast_in_late       : std_logic := '0';
  signal pix_count_mismatch  : std_logic := '0';
  signal word_count_mismatch : std_logic := '0';

  -- Handshakes reais
  signal s_hs : std_logic;
  signal m_hs : std_logic;

  -- AXI-Lite latches
  signal awaddr_lat : std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0) := (others => '0');
  signal wdata_lat  : std_logic_vector(31 downto 0) := (others => '0');
  signal aw_seen : std_logic := '0';
  signal w_seen  : std_logic := '0';

  signal req_start      : std_logic := '0';
  signal req_soft_reset : std_logic := '0';
  signal req_clear      : std_logic := '0';
  signal auto_restart   : std_logic := '0';

  function u32(n : integer) return unsigned is
  begin
    return to_unsigned(n, 32);
  end function;

  constant A_CTRL  : std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0) := x"00";
  constant A_STAT  : std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0) := x"04";
  constant A_PIXL  : std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0) := x"08";
  constant A_WORDL : std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0) := x"0C";
  constant A_CTPI  : std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0) := x"10";
  constant A_CNWD  : std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0) := x"14";
  constant A_CLER  : std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0) := x"18";

begin

  rst <= not aresetn;

  -- portas
  s_axis_tready <= s_axis_tready_i;

  m_axis_tdata  <= m_axis_tdata_i;
  m_axis_tvalid <= m_axis_tvalid_i;
  m_axis_tlast  <= m_axis_tlast_i;

  s_axi_awready <= s_axi_awready_i;
  s_axi_wready  <= s_axi_wready_i;
  s_axi_arready <= s_axi_arready_i;

  s_axi_bresp   <= s_axi_bresp_i;
  s_axi_bvalid  <= s_axi_bvalid_i;

  s_axi_rdata   <= s_axi_rdata_i;
  s_axi_rresp   <= s_axi_rresp_i;
  s_axi_rvalid  <= s_axi_rvalid_i;

  -- =========================================================
  -- AXIS entrada -> core (SEM deadlock)
  -- =========================================================
  pixel_in <= unsigned(s_axis_tdata);

  -- Durante frame: tready segue o in_ready do core
  -- Fora de frame: tready 0 (não consome)
  s_axis_tready_i <= '1' when (in_frame='1' and in_ready='1') else '0';

  -- handshake real de pixel
  s_hs <= '1' when (in_frame='1' and s_axis_tvalid='1' and s_axis_tready_i='1') else '0';

  -- valid para o core deve ser o valid do AXIS (gate por in_frame)
  in_valid <= '1' when (in_frame='1' and s_axis_tvalid='1') else '0';

  -- handshake de saída
  m_hs <= '1' when (m_axis_tvalid_i='1' and m_axis_tready='1') else '0';

  -- =========================================================
  -- Core
  -- =========================================================
  u_core: entity work.hog_pipeline_link
    port map (
      clk         => aclk,
      rst         => rst,
      frame_start => frame_start,

      in_valid    => in_valid,
      in_ready    => in_ready,
      pixel_in    => pixel_in,

      m_axis_tdata  => m_axis_tdata_i,
      m_axis_tvalid => m_axis_tvalid_i,
      m_axis_tready => m_axis_tready,
      m_axis_tlast  => m_axis_tlast_i,

      frame_done => frame_done_core
    );

  -- =========================================================
  -- Estado/contadores/latches
  -- =========================================================
  p_main: process(aclk)
    variable word_cnt_next : unsigned(31 downto 0);
    variable pix_last_ok   : boolean;
  begin
    if rising_edge(aclk) then
      if rst='1' then
        frame_start <= '0';
        in_frame    <= '0';

        pix_cnt  <= (others=>'0');
        word_cnt <= (others=>'0');

        pix_cnt_last  <= (others=>'0');
        word_cnt_last <= (others=>'0');

        busy_latched       <= '0';
        frame_done_latched <= '0';
        error_latched      <= '0';

        tlast_in_early      <= '0';
        tlast_in_late       <= '0';
        pix_count_mismatch  <= '0';
        word_count_mismatch <= '0';

      else
        frame_start <= '0';

        -- soft reset
        if req_soft_reset='1' then
          in_frame <= '0';
          pix_cnt  <= (others=>'0');
          word_cnt <= (others=>'0');
          pix_cnt_last  <= (others=>'0');
          word_cnt_last <= (others=>'0');

          busy_latched       <= '0';
          frame_done_latched <= '0';
          error_latched      <= '0';

          tlast_in_early      <= '0';
          tlast_in_late       <= '0';
          pix_count_mismatch  <= '0';
          word_count_mismatch <= '0';
        end if;

        -- clear flags
        if req_clear='1' then
          frame_done_latched <= '0';
          error_latched      <= '0';
          tlast_in_early      <= '0';
          tlast_in_late       <= '0';
          pix_count_mismatch  <= '0';
          word_count_mismatch <= '0';
        end if;

        -- START: gera frame_start e abre janela de recepção
        if req_start='1' then
          frame_start <= '1';
          in_frame    <= '1';

          pix_cnt  <= (others=>'0');
          word_cnt <= (others=>'0');

          busy_latched <= '1';
          -- opcional: limpar latches do frame anterior ao dar start
          frame_done_latched <= '0';
        end if;

        -- contagem de pixels (só quando handshake real)
        if s_hs='1' then
          if s_axis_tlast='1' then
            if pix_cnt /= u32(TOTAL_PIXELS_IN-1) then
              tlast_in_early <= '1';
              error_latched  <= '1';
            end if;
          end if;

          pix_cnt <= pix_cnt + 1;

          if pix_cnt = u32(TOTAL_PIXELS_IN-1) then
            if s_axis_tlast='0' then
              tlast_in_late <= '1';
              error_latched <= '1';
            end if;

            in_frame     <= '0';
            pix_cnt_last <= u32(TOTAL_PIXELS_IN);
          end if;
        end if;

        -- contagem de words saída
        if m_hs='1' then
          word_cnt <= word_cnt + 1;
        end if;

        -- fim lógico do frame
        if frame_done_core='1' then
          frame_done_latched <= '1';
          busy_latched       <= '0';

          if m_hs='1' then
            word_cnt_next := word_cnt + 1;
          else
            word_cnt_next := word_cnt;
          end if;

          word_cnt_last <= word_cnt_next;

          if word_cnt_next /= u32(NUM_WORDS) then
            word_count_mismatch <= '1';
            error_latched       <= '1';
          end if;

          pix_last_ok := (pix_cnt_last = u32(TOTAL_PIXELS_IN));
          if not pix_last_ok then
            pix_count_mismatch <= '1';
            error_latched      <= '1';
          end if;

          if auto_restart='1' then
            frame_start <= '1';
            in_frame    <= '1';
            pix_cnt  <= (others=>'0');
            word_cnt <= (others=>'0');
            busy_latched <= '1';
            frame_done_latched <= '0';
          end if;
        end if;

      end if;
    end if;
  end process;

  -- =========================================================
  -- AXI-Lite (igual ao seu, só mantendo pulsos)
  -- =========================================================
  s_axi_bresp_i <= "00";
  s_axi_rresp_i <= "00";

  s_axi_awready_i <= '1' when (s_axi_bvalid_i='0' and aw_seen='0') else '0';
  s_axi_wready_i  <= '1' when (s_axi_bvalid_i='0' and w_seen='0')  else '0';
  s_axi_arready_i <= '1' when (s_axi_rvalid_i='0') else '0';

  p_axil: process(aclk)
    variable addr : std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
  begin
    if rising_edge(aclk) then
      if rst='1' then
        awaddr_lat <= (others=>'0');
        wdata_lat  <= (others=>'0');
        aw_seen    <= '0';
        w_seen     <= '0';

        s_axi_bvalid_i <= '0';
        s_axi_rvalid_i <= '0';
        s_axi_rdata_i  <= (others=>'0');

        req_start      <= '0';
        req_soft_reset <= '0';
        req_clear      <= '0';
        auto_restart   <= '0';

      else
        req_start      <= '0';
        req_soft_reset <= '0';
        req_clear      <= '0';

        if (s_axi_awvalid='1' and s_axi_awready_i='1') then
          awaddr_lat <= s_axi_awaddr;
          aw_seen    <= '1';
        end if;

        if (s_axi_wvalid='1' and s_axi_wready_i='1') then
          wdata_lat <= s_axi_wdata(31 downto 0);
          w_seen    <= '1';
        end if;

        if (s_axi_bvalid_i='0' and aw_seen='1' and w_seen='1') then
          addr := awaddr_lat;

          case addr is
            when A_CTRL =>
              if wdata_lat(0)='1' then req_start <= '1'; end if;
              if wdata_lat(1)='1' then req_soft_reset <= '1'; end if;
              auto_restart <= wdata_lat(2);

            when A_CLER =>
              if wdata_lat(0)='1' then req_clear <= '1'; end if;

            when others =>
              null;
          end case;

          s_axi_bvalid_i <= '1';
          aw_seen <= '0';
          w_seen  <= '0';

        elsif (s_axi_bvalid_i='1' and s_axi_bready='1') then
          s_axi_bvalid_i <= '0';
        end if;

        if (s_axi_arvalid='1' and s_axi_arready_i='1') then
          addr := s_axi_araddr;

          case addr is
            when A_CTRL =>
              s_axi_rdata_i <= (others=>'0');
              s_axi_rdata_i(2) <= auto_restart;

            when A_STAT =>
              s_axi_rdata_i <= (others=>'0');
              s_axi_rdata_i(0) <= busy_latched;
              s_axi_rdata_i(1) <= frame_done_latched;
              s_axi_rdata_i(2) <= error_latched;
              s_axi_rdata_i(3) <= tlast_in_early;
              s_axi_rdata_i(4) <= tlast_in_late;
              s_axi_rdata_i(5) <= pix_count_mismatch;
              s_axi_rdata_i(6) <= word_count_mismatch;

            when A_PIXL =>
              s_axi_rdata_i <= std_logic_vector(pix_cnt_last);

            when A_WORDL =>
              s_axi_rdata_i <= std_logic_vector(word_cnt_last);

            when A_CTPI =>
              s_axi_rdata_i <= std_logic_vector(u32(TOTAL_PIXELS_IN));

            when A_CNWD =>
              s_axi_rdata_i <= std_logic_vector(u32(NUM_WORDS));

            when others =>
              s_axi_rdata_i <= (others=>'0');
          end case;

          s_axi_rvalid_i <= '1';

        elsif (s_axi_rvalid_i='1' and s_axi_rready='1') then
          s_axi_rvalid_i <= '0';
        end if;

      end if;
    end if;
  end process;

end architecture;

----------------------------------------------------------------------------------
-- Nome: Nathan Spinola Zeidan
-- Matricula: 180025864
-- Curso: Engenharia Eletronica
-- Instituicao: Universidade de Brasilia - UnB
-- Projeto: Acelerador HOG em FPGA
-- Data: Dezembro de 2025
--
----------------------------------------------------------------------------------
-- Arquivo: hogpack.vhd
-- Modulo: HOGPack - Parametrizacao Global do Pipeline HOG
--
-- Descricao Geral
-- ------------------------------------------------------------------------------
-- Este package centraliza todas as parametrizacoes utilizadas no pipeline HOG 
-- (Histogram of Oriented Gradients). Ele atua como o arquivo de configuracao 
-- principal do projeto, garantindo consistencia e facilitando a alteracao de 
-- parametros do sistema.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use ieee.math_real.all;  -- log2, sqrt, ceil

package hogpack is
  -- =========================
  -- PARÂMETROS AJUSTÁVEIS
  -- =========================
  constant ROI_SIZE    : integer := 32; -- 32,64,128...
  constant PADDING     : integer := 1;
  constant CELL_SIZE   : integer := 8;  -- fixo
  constant NUM_BINS    : integer := 9;  -- fixo
  constant PIXEL_BITS  : integer := 8;

  -- bloco quadrado em células: 2,3,4...
  constant BLOCK_SIDE  : integer := 2;

  -- =========================
  -- DERIVADOS
  -- =========================
  constant PAD_SIZE : integer := ROI_SIZE + 2*PADDING;
  constant TOTAL_PIXELS_IN : integer := PAD_SIZE * PAD_SIZE;

  constant NUM_CELLS_X     : integer := ROI_SIZE / CELL_SIZE;
  constant NUM_CELLS_Y     : integer := ROI_SIZE / CELL_SIZE;
  constant NUM_CELLS_TOTAL : integer := NUM_CELLS_X * NUM_CELLS_Y;

  constant BLOCK_SIZE  : integer := BLOCK_SIDE * BLOCK_SIDE;

  -- stride 1 célula (bloco deslizante)
  constant TOTAL_BLOCKS : integer :=
    (NUM_CELLS_X - BLOCK_SIDE + 1) * (NUM_CELLS_Y - BLOCK_SIDE + 1);
    -- índices
  constant NUM_CELLS_BITS : integer := integer(ceil(log2(real(NUM_CELLS_TOTAL))));
  constant BLOCK_COUNTER_BITS : integer := integer(ceil(log2(real(TOTAL_BLOCKS + 1))));
    
  -- =========================
  -- BITS / LARGURAS 
  -- =========================
  constant GRAD_BITS : integer := 11;
  constant MAG_BITS      : integer := 11; -- mag aprox com margem
  constant HIST_BIN_BITS : integer := 19; -- acum célula 

  constant HISTOGRAM_BITS_PER_BLOCK : integer := NUM_BINS * BLOCK_SIZE; -- binário

  -- Para média: soma de bins do bloco (antes da binarização)
  constant SUM_BLOCK_BITS : integer :=
    HIST_BIN_BITS + integer(ceil(log2(real(HISTOGRAM_BITS_PER_BLOCK))));

  -- AXI packing
  constant AXI_WORD_WIDTH  : integer := 32;
  constant WORDS_PER_BLOCK : integer :=
    (HISTOGRAM_BITS_PER_BLOCK + AXI_WORD_WIDTH - 1) / AXI_WORD_WIDTH;

  constant NUM_WORDS      : integer := TOTAL_BLOCKS * WORDS_PER_BLOCK;
  constant NUM_WORDS_BITS : integer := integer(ceil(log2(real(NUM_WORDS + 1))));
  -- =========================
  -- TAN/LUT (Proposta 3)
  -- =========================
  constant TAN_SCALE_BITS : integer := 10;
  constant TAN_SCALE      : unsigned(TAN_SCALE_BITS-1 downto 0) := to_unsigned(2**TAN_SCALE_BITS, TAN_SCALE_BITS); -- 1024

  -- tan(20)=0.363970..., tan(40)=0.839099..., tan(60)=1.732050..., tan(80)=5.671282...
  -- valores escalados por 1024 e arredondados:
  constant TAN_20 : unsigned(TAN_SCALE_BITS-1 downto 0) := to_unsigned( 373, TAN_SCALE_BITS);  -- round(0.36397*1024)
  constant TAN_40 : unsigned(TAN_SCALE_BITS-1 downto 0) := to_unsigned( 859, TAN_SCALE_BITS);  -- round(0.83910*1024)
  constant TAN_60 : unsigned(TAN_SCALE_BITS-1 downto 0) := to_unsigned(1773, TAN_SCALE_BITS);  -- round(1.73205*1024)
  constant TAN_80 : unsigned(TAN_SCALE_BITS-1 downto 0) := to_unsigned(5807, TAN_SCALE_BITS);  -- round(5.67128*1024)

  -- =========================
  -- TIPOS
  -- =========================
  subtype bin_u is unsigned(HIST_BIN_BITS-1 downto 0);

  type CellHist_t  is array(0 to NUM_BINS-1) of bin_u;
  type ImgCellHist_t is array(0 to NUM_CELLS_TOTAL-1) of CellHist_t;
  type BlockHist_t is array(0 to BLOCK_SIZE-1) of CellHist_t;
end hogpack;
 

