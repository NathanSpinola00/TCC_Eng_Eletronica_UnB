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
