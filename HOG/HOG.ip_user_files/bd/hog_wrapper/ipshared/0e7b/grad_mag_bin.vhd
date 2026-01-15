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
