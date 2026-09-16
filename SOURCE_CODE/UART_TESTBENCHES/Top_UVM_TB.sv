`timescale 1ns/1ps

interface UART_IF;

    logic clk;
    logic rst_n;

    logic [7:0] tx_data;
    logic tx_valid;
    logic tx_ready;
    logic tx;

    logic rx;
    logic [7:0] rx_data;
    logic rx_valid;
    logic rx_ready;

    logic parity_error;
    logic frame_error;

endinterface


package UART_UVM_PKG;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    localparam int CLK_FREQ = 50_000_000;  // DUT system clock frequency
    localparam int BAUD_RATE = 115200;  // DUT UART baud rate
    localparam realtime BIT_TIME = 1_000_000_000.0 / BAUD_RATE;  // UART bit period in nanoseconds

    localparam int NUM_TX = 4;  // Number of TX transactions in the test
    localparam int NUM_RX = 4;  // Number of RX transactions in the test

    typedef enum {UART_TX_OP, UART_RX_OP} UART_OPERATION_E;  // Identifies the direction of a transaction


    class UART_TRANSACTION extends uvm_sequence_item;

        rand UART_OPERATION_E operation;  // Selects TX or RX operation
        rand bit [7:0] data;  // UART transaction data

        `uvm_object_utils_begin(UART_TRANSACTION)
            `uvm_field_enum(UART_OPERATION_E, operation, UVM_ALL_ON)
            `uvm_field_int(data, UVM_ALL_ON)
        `uvm_object_utils_end

        function new(input string name = "UART_TRANSACTION");
            super.new(name);
        endfunction

    endclass


    class UART_SEQUENCER extends uvm_sequencer #(UART_TRANSACTION);

        `uvm_component_utils(UART_SEQUENCER)

        function new(input string name = "UART_SEQUENCER", uvm_component parent = null);
            super.new(name, parent);
        endfunction

    endclass


    class UART_DRIVER extends uvm_driver #(UART_TRANSACTION);

        `uvm_component_utils(UART_DRIVER)

        virtual UART_IF vif;  // Virtual interface connects UVM driver to DUT signals

        uvm_analysis_port #(UART_TRANSACTION) tx_expected_ap;  // Expected TX transactions sent to scoreboard
        uvm_analysis_port #(UART_TRANSACTION) rx_expected_ap;  // Expected RX transactions sent to scoreboard

        function new(input string name = "UART_DRIVER", uvm_component parent = null);
            super.new(name, parent);
            tx_expected_ap = new("tx_expected_ap", this);
            rx_expected_ap = new("rx_expected_ap", this);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);

            if (!uvm_config_db #(virtual UART_IF)::get(this, "", "vif", vif))
                `uvm_fatal("NOVIF", "UART_IF was not found in the UVM configuration database")
        endfunction

        task run_phase(uvm_phase phase);

            UART_TRANSACTION tr;  // Holds the transaction received from the sequencer

            wait (vif.rst_n === 1'b1);  // Do not drive the DUT until reset is released

            forever begin

                seq_item_port.get_next_item(tr);  // Request the next transaction from the sequencer

                if (tr.operation == UART_TX_OP)
                    drive_tx(tr.data);  // Drive a host-side TX transaction
                else
                    drive_rx(tr.data);  // Drive a serial RX frame

                if (tr.operation == UART_TX_OP)
                    tx_expected_ap.write(tr);  // Send accepted TX transaction to the TX scoreboard queue
                else
                    rx_expected_ap.write(tr);  // Send transmitted RX frame to the RX scoreboard queue

                seq_item_port.item_done();  // Inform the sequencer that the transaction is complete

            end

        endtask


        task drive_tx(input bit [7:0] data);

            @(negedge vif.clk);  // Change stimulus away from the DUT sampling edge

            vif.tx_data <= data;  // Place data on the DUT TX input
            vif.tx_valid <= 1'b1;  // Request a TX transfer

            do
                @(posedge vif.clk);  // Wait for the DUT to sample the request
            while (vif.tx_ready !== 1'b1);  // Hold valid until the DUT accepts the transfer

            @(negedge vif.clk);  // Move stimulus away from the next sampling edge

            vif.tx_valid <= 1'b0;  // End the TX transfer
            vif.tx_data <= '0;  // Return input data bus to zero

        endtask


        task drive_rx(input bit [7:0] data);

            vif.rx <= 1'b0;  // Drive UART start bit
            #(BIT_TIME);  // Hold start bit for one UART bit period

            for (int i = 0; i < 8; i++) begin
                vif.rx <= data[i];  // UART transmits data LSB first
                #(BIT_TIME);  // Hold each data bit for one UART bit period
            end

            vif.rx <= 1'b1;  // Drive UART stop bit
            #(BIT_TIME);  // Hold stop bit for one UART bit period

        endtask

    endclass


    class UART_TX_MONITOR extends uvm_monitor;

        `uvm_component_utils(UART_TX_MONITOR)

        virtual UART_IF vif;  // Virtual interface used to observe the DUT TX pin

        uvm_analysis_port #(UART_TRANSACTION) analysis_ap;  // Sends decoded TX frames to scoreboard

        function new(input string name = "UART_TX_MONITOR", uvm_component parent = null);
            super.new(name, parent);
            analysis_ap = new("analysis_ap", this);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);

            if (!uvm_config_db #(virtual UART_IF)::get(this, "", "vif", vif))
                `uvm_fatal("NOVIF", "UART_IF was not found in the UVM configuration database")
        endfunction

        task run_phase(uvm_phase phase);

            UART_TRANSACTION tr;  // Stores a decoded UART TX frame

            forever begin

                @(negedge vif.tx);  // Detect the falling edge that begins a UART frame

                if (vif.rst_n !== 1'b1)
                    continue;  // Ignore activity during reset

                #(BIT_TIME / 2.0);  // Move to the center of the start bit

                if (vif.tx !== 1'b0)
                    continue;  // Reject an invalid start-bit observation

                tr = UART_TRANSACTION::type_id::create("tr");  // Create a decoded TX transaction

                tr.operation = UART_TX_OP;  // Identify this transaction as TX
                tr.data = '0;  // Clear the data field before sampling

                #(BIT_TIME);  // Move from start-bit center to D0 center

                for (int i = 0; i < 8; i++) begin
                    tr.data[i] = vif.tx;  // Sample each transmitted data bit
                    #(BIT_TIME);  // Move to the next bit center
                end

                if (vif.tx !== 1'b1)
                    `uvm_error("TX_MON", "UART TX stop bit is not HIGH")

                analysis_ap.write(tr);  // Send decoded frame to scoreboard

            end

        endtask

    endclass


    class UART_RX_MONITOR extends uvm_monitor;

        `uvm_component_utils(UART_RX_MONITOR)

        virtual UART_IF vif;  // Virtual interface used to observe DUT RX output

        uvm_analysis_port #(UART_TRANSACTION) analysis_ap;  // Sends received data to scoreboard

        function new(input string name = "UART_RX_MONITOR", uvm_component parent = null);
            super.new(name, parent);
            analysis_ap = new("analysis_ap", this);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);

            if (!uvm_config_db #(virtual UART_IF)::get(this, "", "vif", vif))
                `uvm_fatal("NOVIF", "UART_IF was not found in the UVM configuration database")
        endfunction

        task run_phase(uvm_phase phase);

            UART_TRANSACTION tr;  // Stores a received UART transaction

            forever begin

                @(posedge vif.rx_valid);  // Detect valid data produced by the DUT

                #1;  // Allow DUT nonblocking assignments to update visible outputs

                tr = UART_TRANSACTION::type_id::create("tr");  // Create a received transaction

                tr.operation = UART_RX_OP;  // Identify this transaction as RX
                tr.data = vif.rx_data;  // Capture received data

                analysis_ap.write(tr);  // Send received data to scoreboard

            end

        endtask

    endclass


    class UART_SCOREBOARD extends uvm_scoreboard;

        `uvm_component_utils(UART_SCOREBOARD)

        uvm_tlm_analysis_fifo #(UART_TRANSACTION) tx_expected_fifo;  // Expected TX transaction queue
        uvm_tlm_analysis_fifo #(UART_TRANSACTION) tx_actual_fifo;  // Observed TX transaction queue

        uvm_tlm_analysis_fifo #(UART_TRANSACTION) rx_expected_fifo;  // Expected RX transaction queue
        uvm_tlm_analysis_fifo #(UART_TRANSACTION) rx_actual_fifo;  // Observed RX transaction queue

        int tx_matches;  // Number of correctly transmitted frames
        int rx_matches;  // Number of correctly received frames

        function new(input string name = "UART_SCOREBOARD", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);

            super.build_phase(phase);

            tx_expected_fifo = new("tx_expected_fifo", this);  // Create expected TX queue
            tx_actual_fifo = new("tx_actual_fifo", this);  // Create actual TX queue
            rx_expected_fifo = new("rx_expected_fifo", this);  // Create expected RX queue
            rx_actual_fifo = new("rx_actual_fifo", this);  // Create actual RX queue

            tx_matches = 0;  // Initialize TX match counter
            rx_matches = 0;  // Initialize RX match counter

        endfunction


        task run_phase(uvm_phase phase);

            fork
                compare_tx();  // Continuously compare expected and observed TX transactions
                compare_rx();  // Continuously compare expected and observed RX transactions
            join

        endtask


        task compare_tx();

            UART_TRANSACTION expected;  // Expected TX transaction
            UART_TRANSACTION actual;  // Observed TX transaction

            forever begin

                tx_expected_fifo.get(expected);  // Wait for the next expected TX transaction
                tx_actual_fifo.get(actual);  // Wait for the next observed TX transaction

                if (expected.data !== actual.data) begin
                    `uvm_error("TX_SCB", $sformatf("TX mismatch: expected 0x%02h, actual 0x%02h", expected.data, actual.data))
                end
                else begin
                    tx_matches++;  // Record a successful TX comparison
                    `uvm_info("TX_SCB", $sformatf("TX matched: 0x%02h", actual.data), UVM_MEDIUM)
                end

            end

        endtask


        task compare_rx();

            UART_TRANSACTION expected;  // Expected RX transaction
            UART_TRANSACTION actual;  // Observed RX transaction

            forever begin

                rx_expected_fifo.get(expected);  // Wait for the next expected RX transaction
                rx_actual_fifo.get(actual);  // Wait for the next observed RX transaction

                if (expected.data !== actual.data) begin
                    `uvm_error("RX_SCB", $sformatf("RX mismatch: expected 0x%02h, actual 0x%02h", expected.data, actual.data))
                end
                else begin
                    rx_matches++;  // Record a successful RX comparison
                    `uvm_info("RX_SCB", $sformatf("RX matched: 0x%02h", actual.data), UVM_MEDIUM)
                end

            end

        endtask

    endclass


    class UART_AGENT extends uvm_agent;

        `uvm_component_utils(UART_AGENT)

        UART_SEQUENCER sequencer;  // Generates UART sequence items
        UART_DRIVER driver;  // Drives transactions into the DUT
        UART_TX_MONITOR tx_monitor;  // Monitors the DUT TX serial output
        UART_RX_MONITOR rx_monitor;  // Monitors the DUT RX data output

        function new(input string name = "UART_AGENT", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);

            super.build_phase(phase);

            sequencer = UART_SEQUENCER::type_id::create("sequencer", this);  // Create sequencer
            driver = UART_DRIVER::type_id::create("driver", this);  // Create driver
            tx_monitor = UART_TX_MONITOR::type_id::create("tx_monitor", this);  // Create TX monitor
            rx_monitor = UART_RX_MONITOR::type_id::create("rx_monitor", this);  // Create RX monitor

        endfunction

        function void connect_phase(uvm_phase phase);

            super.connect_phase(phase);

            driver.seq_item_port.connect(sequencer.seq_item_export);  // Connect sequencer to driver

        endfunction

    endclass


    class UART_ENV extends uvm_env;

        `uvm_component_utils(UART_ENV)

        UART_AGENT agent;  // Contains the active driver and monitors
        UART_SCOREBOARD scoreboard;  // Checks expected versus actual behavior

        function new(input string name = "UART_ENV", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);

            super.build_phase(phase);

            agent = UART_AGENT::type_id::create("agent", this);  // Create UART agent
            scoreboard = UART_SCOREBOARD::type_id::create("scoreboard", this);  // Create scoreboard

        endfunction

        function void connect_phase(uvm_phase phase);

            super.connect_phase(phase);

            agent.driver.tx_expected_ap.connect(scoreboard.tx_expected_fifo.analysis_export);  // Connect expected TX stream
            agent.driver.rx_expected_ap.connect(scoreboard.rx_expected_fifo.analysis_export);  // Connect expected RX stream

            agent.tx_monitor.analysis_ap.connect(scoreboard.tx_actual_fifo.analysis_export);  // Connect observed TX stream
            agent.rx_monitor.analysis_ap.connect(scoreboard.rx_actual_fifo.analysis_export);  // Connect observed RX stream

        endfunction

    endclass


    class UART_SEQUENCE extends uvm_sequence #(UART_TRANSACTION);

        `uvm_object_utils(UART_SEQUENCE)

        function new(input string name = "UART_SEQUENCE");
            super.new(name);
        endfunction

        task body();

            UART_TRANSACTION tr;  // Sequence item used to send transactions to the driver

            bit [7:0] tx_values[NUM_TX] = '{8'h55, 8'h96, 8'hA5, 8'hFF};  // TX test patterns
            bit [7:0] rx_values[NUM_RX] = '{8'h3C, 8'h00, 8'h81, 8'hF0};  // RX test patterns

            foreach (tx_values[i]) begin

                tr = UART_TRANSACTION::type_id::create($sformatf("tx_tr_%0d", i));  // Create TX transaction

                start_item(tr);  // Begin sequence-item handshake
                tr.operation = UART_TX_OP;  // Select TX operation
                tr.data = tx_values[i];  // Assign TX test data
                finish_item(tr);  // Send transaction to driver

            end

            foreach (rx_values[i]) begin

                tr = UART_TRANSACTION::type_id::create($sformatf("rx_tr_%0d", i));  // Create RX transaction

                start_item(tr);  // Begin sequence-item handshake
                tr.operation = UART_RX_OP;  // Select RX operation
                tr.data = rx_values[i];  // Assign RX test data
                finish_item(tr);  // Send transaction to driver

            end

        endtask

    endclass


    class UART_TEST extends uvm_test;

        `uvm_component_utils(UART_TEST)

        UART_ENV env;  // Top-level UVM environment

        function new(input string name = "UART_TEST", uvm_component parent = null);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);

            super.build_phase(phase);

            env = UART_ENV::type_id::create("env", this);  // Create UART environment

        endfunction


        task run_phase(uvm_phase phase);

            UART_SEQUENCE seq;  // Test sequence

            phase.raise_objection(this);  // Keep UVM simulation alive while test executes

            seq = UART_SEQUENCE::type_id::create("seq");  // Create test sequence
            seq.start(env.agent.sequencer);  // Start sequence on the UART sequencer

            wait (env.scoreboard.tx_matches == NUM_TX);  // Wait until all TX frames pass
            wait (env.scoreboard.rx_matches == NUM_RX);  // Wait until all RX frames pass

            #(BIT_TIME);  // Allow final DUT activity to settle

            phase.drop_objection(this);  // Allow UVM simulation to finish

        endtask

    endclass

endpackage


module UART_UVM_TB;

    import uvm_pkg::*;
    import UART_UVM_PKG::*;

    UART_IF vif();  // Interface instance connecting UVM components to the DUT

    UART_Top #(.CLK_FREQ(CLK_FREQ),
               .BAUD_RATE(BAUD_RATE),
               .ACC_WIDTH(32),
               .DATA_BITS(8),
               .STOP_BITS(1),
               .PARITY_EN(0),
               .PARITY_ODD(0),
               .FIFO_DEPTH(16))
    URT_TP (.clk(vif.clk),
         .rst_n(vif.rst_n),
         .tx_data(vif.tx_data),
         .tx_valid(vif.tx_valid),
         .tx_ready(vif.tx_ready),
         .tx(vif.tx),
         .rx(vif.rx),
         .rx_data(vif.rx_data),
         .rx_valid(vif.rx_valid),
         .rx_ready(vif.rx_ready),
         .parity_error(vif.parity_error),
         .frame_error(vif.frame_error));

    initial begin

        vif.clk = 1'b0;  // Initialize system clock
        forever #10 vif.clk = ~vif.clk;  // Generate 50 MHz system clock

    end


    initial begin

        vif.rst_n = 1'b0;  // Assert active-low reset
        vif.tx_data = '0;  // Initialize TX data input
        vif.tx_valid = 1'b0;  // Initialize TX valid input
        vif.rx = 1'b1;  // UART RX line is idle HIGH
        vif.rx_ready = 1'b1;  // Always accept received data in this smoke test

        repeat (10) @(posedge vif.clk);  // Hold reset for ten system-clock cycles

        vif.rst_n = 1'b1;  // Release reset

    end


    initial begin

        uvm_config_db #(virtual UART_IF)::set(null, "*", "vif", vif);  // Make interface available to all UVM components

        run_test("UART_TEST");  // Start the UVM test

    end
endmodule