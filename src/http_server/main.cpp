#include <boost/asio.hpp>
#include <boost/beast/core.hpp>
#include <boost/beast/http.hpp>
#include <boost/beast/version.hpp>
#include <chrono>
#include <cstdlib>
#include <ctime>
#include <iostream>
#include <memory>
#include <string>
#include <span>

namespace beast = boost::beast;// from <boost/beast.hpp>
namespace http = beast::http;// from <boost/beast/http.hpp>
namespace net = boost::asio;// from <boost/asio.hpp>
using tcp = boost::asio::ip::tcp;// from <boost/asio/ip/tcp.hpp>

namespace my_program_state {
std::size_t request_count()
{
  static std::size_t count = 0;
  return ++count;
}

std::time_t now() { return std::time(nullptr); }
}// namespace my_program_state

class http_connection : public std::enable_shared_from_this<http_connection>
{
  constexpr static size_t buffer_size = 8192;
  constexpr static int deadline_timeout = 60;
public:
  explicit http_connection(tcp::socket socket) : m_socket(std::move(socket)) {}

  // Initiate the asynchronous operations associated with the connection.
  void start()
  {
    read_request();
    check_deadline();
  }

private:
  // The socket for the currently connected client.
  tcp::socket m_socket;

  // The buffer for performing reads.
  beast::flat_buffer m_buffer{ buffer_size };

  // The request message.
  http::request<http::string_body> m_request;

  // The response message.
  http::response<http::dynamic_body> m_response;

  // The timer for putting a deadline on connection processing.
  net::steady_timer m_deadline{ m_socket.get_executor(), std::chrono::seconds(deadline_timeout) };

  // Asynchronously receive a complete request message.
  void read_request()
  {
    auto self = shared_from_this();

    http::async_read(m_socket, m_buffer, m_request, [self](beast::error_code error_code, std::size_t bytes_transferred) {
      boost::ignore_unused(bytes_transferred);
      if (!error_code) { self->process_request(); }
    });
  }

  // Determine what needs to be done with the request message.
  void process_request()
  {
    m_response.version(m_request.version());
    m_response.keep_alive(false);

    switch (m_request.method()) {
    case http::verb::get:
      if (const auto x = m_request.find("X-Extra-Header"); x != m_request.end()) {
        std::cout << "Found header X-Extra-Header: " << (*x).value() << "\n";
      }
      m_response.result(http::status::ok);
      m_response.set(http::field::server, "Beast");
      create_response();
      break;

    default:
      // We return responses indicating an error if
      // we do not recognize the request method.
      std::cout << m_request.body() << "\n";
      m_response.result(http::status::bad_request);
      m_response.set(http::field::content_type, "text/plain");
      beast::ostream(m_response.body()) << "Invalid request-method '" << std::string(m_request.method_string()) << "'";
      break;
    }

    write_response();
  }

  // Construct a response message based on the program state.
  void create_response()
  {
    if (m_request.target() == "/count") {
      m_response.set(http::field::content_type, "text/html");
      beast::ostream(m_response.body()) << "<html>\n"
                                       << "<head><title>Request count</title></head>\n"
                                       << "<body>\n"
                                       << "<h1>Request count</h1>\n"
                                       << "<p>There have been " << my_program_state::request_count()
                                       << " requests so far.</p>\n"
                                       << "</body>\n"
                                       << "</html>\n";
    } else if (m_request.target() == "/time") {
      m_response.set(http::field::content_type, "text/html");
      beast::ostream(m_response.body()) << "<html>\n"
                                       << "<head><title>Current time</title></head>\n"
                                       << "<body>\n"
                                       << "<h1>Current time</h1>\n"
                                       << "<p>The current time is " << my_program_state::now()
                                       << " seconds since the epoch.</p>\n"
                                       << "</body>\n"
                                       << "</html>\n";
    } else {
      m_response.result(http::status::not_found);
      m_response.set(http::field::content_type, "text/plain");
      beast::ostream(m_response.body()) << "File not found\r\n";
    }
  }

  // Asynchronously transmit the response message.
  void write_response()
  {
    auto self = shared_from_this();

    m_response.content_length(m_response.body().size());

    http::async_write(m_socket, m_response, [self](beast::error_code error_code, std::size_t) {
      self->m_socket.shutdown(tcp::socket::shutdown_send, error_code);
      self->m_deadline.cancel();
    });
  }

  // Check whether we have spent enough time on this connection.
  void check_deadline()
  {
    auto self = shared_from_this();

    m_deadline.async_wait([self](beast::error_code error_code) {
      if (!error_code) {
        // Close socket to cancel any outstanding operation.
        self->m_socket.close(error_code);
      }
    });
  }
};

// "Loop" forever accepting new connections.
void http_server(tcp::acceptor &acceptor, tcp::socket &socket)
{
  acceptor.async_accept(socket, [&](beast::error_code error_code) {
    if (!error_code) { std::make_shared<http_connection>(std::move(socket))->start(); }
    http_server(acceptor, socket);
  });
}

int main(int argc, char* argv[])
{
  auto const args = std::span(argv, static_cast<size_t>(argc));

  try {
    // Check command line arguments.
    if (argc != 3) {
      std::cerr << "Usage: " << args[0] << " <address> <port>\n";
      std::cerr << "  For IPv4, try:\n";
      std::cerr << "    receiver 0.0.0.0 80\n";
      std::cerr << "  For IPv6, try:\n";
      std::cerr << "    receiver 0::0 80\n";
      return EXIT_FAILURE;
    }

    auto const address = net::ip::make_address((args[1]));
    auto const port = static_cast<unsigned short>(std::strtol(args[2], nullptr, 10));

    net::io_context ioc{ 4 };

    tcp::acceptor acceptor{ ioc, { address, port } };
    tcp::socket socket{ ioc };
    http_server(acceptor, socket);


    std::vector<std::thread> threads;
    for (size_t i = 0; i < 4; i++) {
      threads.emplace_back([&ioc] { ioc.run(); });
    }

    ioc.run();
  } catch (std::exception const &e) {
    std::cerr << "Error: " << e.what() << "\n";
    return EXIT_FAILURE;
  }
}