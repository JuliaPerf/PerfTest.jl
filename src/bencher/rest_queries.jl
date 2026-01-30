
"""
    RESTRequest

A mutable struct that holds all components of a REST request.
"""
mutable struct RESTRequest
    method::String
    url::String
    headers::Dict{String, String}
    query_params::Dict{String, Any}
    body::Dict{String, Any}
    timeout::Int
    
    function RESTRequest()
        new(
            "GET",
            "",
            Dict{String, String}(),
            Dict{String, Any}(),
            Dict{String, Any}(),
            30
        )
    end
end

"""
    RESTRequestBuilder

A builder pattern implementation for constructing REST requests incrementally.
"""
mutable struct RESTRequestBuilder
    request::RESTRequest
    
    RESTRequestBuilder() = new(RESTRequest())
end

# Builder methods
"""
    set_method!(builder::RESTRequestBuilder, method::String)

Set the HTTP method (GET, POST, PUT, DELETE, etc.)
"""
function set_method!(builder::RESTRequestBuilder, method::String)
    builder.request.method = uppercase(method)
    return builder
end

"""
    set_url!(builder::RESTRequestBuilder, url::String)

Set the target URL.
"""
function set_url!(builder::RESTRequestBuilder, url::String)
    builder.request.url = url
    return builder
end

"""
    add_header!(builder::RESTRequestBuilder, key::String, value::String)

Add a single header to the request.
"""
function add_header!(builder::RESTRequestBuilder, key::String, value::String)
    builder.request.headers[key] = value
    return builder
end

"""
    add_headers!(builder::RESTRequestBuilder, headers::Dict{String, String})

Add multiple headers to the request.
"""
function add_headers!(builder::RESTRequestBuilder, headers::Dict{String, String})
    merge!(builder.request.headers, headers)
    return builder
end

"""
    add_query_param!(builder::RESTRequestBuilder, key::String, value)

Add a single query parameter.
"""
function add_query_param!(builder::RESTRequestBuilder, key::String, value)
    builder.request.query_params[key] = value
    return builder
end

"""
    add_query_params!(builder::RESTRequestBuilder, params::Dict{String, Any})

Add multiple query parameters.
"""
function add_query_params!(builder::RESTRequestBuilder, params::Dict{String, Any})
    merge!(builder.request.query_params, params)
    return builder
end

"""
    set_body!(builder::RESTRequestBuilder, body::Dict{String, Any})

Set the request body (for POST, PUT requests).
"""
function set_body!(builder::RESTRequestBuilder, body::Dict{String, Any})
    builder.request.body = body
    return builder
end

"""
    add_body_field!(builder::RESTRequestBuilder, key::String, value)

Add a single field to the request body.
"""
function add_body_field!(builder::RESTRequestBuilder, key::String, value)
    builder.request.body[key] = value
    return builder
end

"""
    set_timeout!(builder::RESTRequestBuilder, timeout::Int)

Set the request timeout in seconds.
"""
function set_timeout!(builder::RESTRequestBuilder, timeout::Int)
    builder.request.timeout = timeout
    return builder
end

"""
    set_api_key!(builder::RESTRequestBuilder, api_key::String; header_name::String="X-API-Key")

Convenience method to set API key in headers.
"""
function set_api_key!(builder::RESTRequestBuilder, api_key::String; header_name::String="X-API-Key")
    add_header!(builder, header_name, api_key)
    return builder
end

"""
    set_bearer_token!(builder::RESTRequestBuilder, token::String)

Convenience method to set Bearer token for authentication.
"""
function set_bearer_token!(builder::RESTRequestBuilder, token::String)
    add_header!(builder, "Authorization", "Bearer $token")
    return builder
end

"""
    build(builder::RESTRequestBuilder)

Build and return the request dictionary.
"""
function build(builder::RESTRequestBuilder)
    req = builder.request
    return Dict(
        "method" => req.method,
        "url" => req.url,
        "headers" => req.headers,
        "query_params" => req.query_params,
        "body" => req.body,
        "timeout" => req.timeout
    )
end

"""
    make_request(request_dict::Dict{String, Any})

Execute a REST request based on the provided dictionary.

Returns a tuple of (success::Bool, response_data::Any, error_message::String)
"""
function make_request(request_dict::Dict{String, Any})
    method = get(request_dict, "method", "GET")
    url = get(request_dict, "url", "")
    headers = get(request_dict, "headers", Dict{String, String}())
    query_params = get(request_dict, "query_params", Dict{String, Any}())
    body = get(request_dict, "body", Dict{String, Any}())
    timeout = get(request_dict, "timeout", 30)
    
    # Validate URL
    if isempty(url)
        return (false, nothing, "URL is required")
    end
    
    # Prepare headers
    if !haskey(headers, "Content-Type") && method in ["POST", "PUT", "PATCH"]
        headers["Content-Type"] = "application/json"
    end
    
    # Build query string
    query_string = HTTP.escapeuri(query_params)
    full_url = isempty(query_string) ? url : "$url?$query_string"
    
    try
        response = if method == "GET"
            HTTP.get(full_url, headers; timeout=timeout)
        elseif method == "POST"
            json_body = JSON.json(body)
            HTTP.post(full_url, headers, json_body; timeout=timeout)
        elseif method == "PUT"
            json_body = JSON.json(body)
            HTTP.put(full_url, headers, json_body; timeout=timeout)
        elseif method == "DELETE"
            HTTP.delete(full_url, headers; timeout=timeout)
        else
            return (false, nothing, "Unsupported HTTP method: $method")
        end
        
        # Parse response
        response_data = try
            JSON.parse(String(response.body))
        catch
            String(response.body)
        end
        
        return (true, response_data, "")
        
    catch e
        error_msg = if isa(e, HTTP.ExceptionRequest.StatusError)
            "HTTP Error $(e.status): $(String(e.response.body))"
        else
            "Request failed: $(string(e))"
        end
        return (false, nothing, error_msg)
    end
end

"""
    quick_get(url::String; headers::Dict{String, String}=Dict{String, String}(), 
            query_params::Dict{String, Any}=Dict{String, Any}())

Convenience function for simple GET requests.
"""
function quick_get(url::String; headers::Dict{String, String}=Dict{String, String}(), 
                query_params::Dict{String, Any}=Dict{String, Any}())
    request_dict = Dict(
        "method" => "GET",
        "url" => url,
        "headers" => headers,
        "query_params" => query_params,
        "body" => Dict{String, Any}(),
        "timeout" => 30
    )
    return make_request(request_dict)
end

"""
    quick_post(url::String, body::Dict{String, Any}; 
            headers::Dict{String, String}=Dict{String, String}())

Convenience function for simple POST requests.
"""
function quick_post(url::String, body::Dict{String, Any}; 
                    headers::Dict{String, String}=Dict{String, String}())
    request_dict = Dict(
        "method" => "POST",
        "url" => url,
        "headers" => headers,
        "query_params" => Dict{String, Any}(),
        "body" => body,
        "timeout" => 30
    )
    return make_request(request_dict)
end