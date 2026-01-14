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
