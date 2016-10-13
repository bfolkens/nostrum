defmodule Mixcord.Rest.Client do
  @moduledoc """
  Interface for Discord's rest API.
  """

  alias Mixcord.Constants
  alias Mixcord.Struct.{Message, User}
  alias Mixcord.Rest
  alias Mixcord.Rest.Ratelimiter

  @doc """
  Send a message to a channel.

  Send `content` to the channel identified with `channel_id`.
  `tts` is an optional parameter that dictates whether the message should be played over text to speech.

  Returns `{:ok, Mixcord.Constructs.Message}` if successful. `{:error, %{status_code: status_code, message: message}}` otherwise.
  """
  @spec create_message(String.t, String.t, boolean) :: {:error, Map.t} | {:ok, Mixcord.Constructs.Message.t}
  def create_message(channel_id, content, tts \\ false) do
    case request(:post, Constants.channel_messages(channel_id), %{content: content, tts: tts}) do
      {:error, status_code: status_code, message: message} ->
        {:error, %{status_code: status_code, message: message}}
      {:ok, body: body} ->
        {:ok, Poison.decode!(body, as: %Message{author: %User{}, mentions: [%User{}]})}
        #https://github.com/devinus/poison/issues/32#issuecomment-172021478
    end
  end

  @doc """
  Send a message to a channel.

  Send `content` to the channel identified with `channel_id`.
  `tts` is an optional parameter that dictates whether the message should be played over text to speech.

  Raises `Mixcord.Errors.ApiError` if error occurs while making the rest call.
  Returns `Mixcord.Constructs.Message` if successful.
  """
  @spec create_message!(String.t, String.t, boolean) :: no_return | Mixcord.Constructs.Message.t
  def create_message!(channel_id, content, tts \\ false) do
    create_message(channel_id, content, tts)
    |> bangify
    |> Poison.decode!(as: %Message{author: %User{}, mentions: [%User{}]})
  end

  @doc """
  Edit a message.

  Edit a message with the given `content`. Message to edit is specified by `channel_id` and `message_id`.

  Returns the edited `{:ok, Mixcord.Constructs.Message}` if successful. `{:error, %{status_code: status_code, message: message}}` otherwise.
  """
  @spec edit_message(String.t, String.t, String.t) :: {:error, Map.t} | {:ok, Mixcord.Constructs.Message.t}
  def edit_message(channel_id, message_id, content) do
    case request(:patch, Constants.channel_message(channel_id, message_id), %{content: content}) do
      {:error, status_code: status_code, message: message} ->
        {:error, %{status_code: status_code, message: message}}
      {:ok, body: body} ->
        {:ok, Poison.decode!(body, as: %Message{author: %User{}})}
    end
  end

  @doc """
  Edit a message.

  Edit a message with the given `content`. Message to edit is specified by `channel_id` and `message_id`.

  Raises `Mixcord.Errors.ApiError` if error occurs while making the rest call.
  Returns the edited `Mixcord.Constructs.Message` if successful.
  """
  @spec edit_message!(String.t, String.t, String.t) :: {:error, Map.t} | {:ok, Mixcord.Constructs.Message.t}
  def edit_message!(channel_id, message_id, content) do
    edit_message(channel_id, message_id, content)
    |> bangify
    |> Poison.decode!(as: %Message{author: %User{}, mentions: [%User{}]})
  end

  @doc """
  Delete a message.

  Delete a message specified by `channel_id` and `message_id`.

  Returns `{:ok}` if successful. `{:error, %{status_code: status_code, message: message}}` otherwise.
  """
  @spec delete_message(String.t, String.t) :: {:error, Map.t} | {:ok}
  def delete_message(channel_id, message_id) do
    case request(:delete, Constants.channel_message(channel_id, message_id), %{}) do
      {:error, status_code: status_code, message: message} ->
        {:error, %{status_code: status_code, message: message}}
      {:ok} ->
        {:ok}
    end
  end

  @doc """
  Delete a message.

  Delete a message specified by `channel_id` and `message_id`.

  Raises `Mixcord.Errors.ApiError` if error occurs while making the rest call.
  Returns {:ok} if successful.
  """
  @spec delete_message!(String.t, String.t) :: {:error, Map.t} | {:ok}
  def delete_message!(channel_id, message_id) do
    delete_message(channel_id, message_id)
    |> bangify
  end

  @doc false
  def request(method, route, body, options \\ []) do
    Ratelimiter.handle_possible_ratelimit(route)
    method
      |> Rest.request(route, body, [], options)
      |> check_for_ratelimit(route)
      |> format_response
  end

  defp check_for_ratelimit(response, route) do
    with %HTTPoison.Response{headers: headers} <- response,
       limit = headers |> List.keyfind("X-RateLimit-Limit", 0) |> Tuple.to_list |> List.last,
       remaining = headers |> List.keyfind("X-RateLimit-Remaining", 0) |> Tuple.to_list |> List.last,
       reset = headers |> List.keyfind("X-RateLimit-Reset", 0) |> Tuple.to_list |> List.last,
       do: {:ok, Ratelimiter.create_bucket(route, limit, remaining, reset)}
    response
  end

  defp format_response(response) do
    case response do
      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, status_code: nil, message: reason}
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, body: body}
      {:ok, %HTTPoison.Response{status_code: 204}} ->
        {:ok}
      {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
        {:error, status_code: status_code, message: body}
    end
  end

  defp bangify(to_bang) do
    case to_bang do
      {:error, %{status_code: code, message: message}} ->
        raise(Mixcord.Error.ApiError, status_code: code, message: message)
      {:ok, body: body} ->
        body
      {:ok} ->
        {:ok}
    end
  end

  @doc """
  Returns the token of the bot.
  """
  @spec get_token() :: String.t
  def get_token() do
    Application.get_env(:mixcord, :token)
  end

end