defmodule LoggerThrottle do
  use GenServer

  @messages_per_minute 120
  @cleanup_interval 60_000 # 1 minute

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def can_send?(message) do
    GenServer.call(__MODULE__, {:can_send?, message})
  end

  def init(_opts) do
    schedule_cleanup()
    {:ok, %{messages: %{}, count: 0, last_reset: System.system_time(:second)}}
  end

  def handle_call({:can_send?, message}, _from, state) do
    current_time = System.system_time(:second)

    # Reset counter if minute has passed
    state = if current_time - state.last_reset >= 60 do
      %{state | count: 0, last_reset: current_time}
    else
      state
    end

    # Check if message was recently sent
    last_sent = Map.get(state.messages, message)
    current_count = state.count

    cond do
      # Too many messages this minute
      current_count >= @messages_per_minute ->
        {:reply, false, state}

      # Message was sent too recently (within 1 second)
      last_sent && (current_time - last_sent) < 1 ->
        {:reply, false, state}

      # OK to send
      true ->
        new_state = %{
          state |
          messages: Map.put(state.messages, message, current_time),
          count: current_count + 1
        }
        {:reply, true, new_state}
    end
  end

  def handle_info(:cleanup, state) do
    current_time = System.system_time(:second)
    # Remove messages older than 1 second
    messages = Enum.reduce(state.messages, %{}, fn {msg, time}, acc ->
      if current_time - time < 1, do: Map.put(acc, msg, time), else: acc
    end)

    schedule_cleanup()
    {:noreply, %{state | messages: messages}}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end
end
