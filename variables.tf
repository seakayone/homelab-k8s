variable "endpoint" {
  type = string
}

variable "api_token" {
  type      = string
  sensitive = true
}

variable "tf_username" {
  type = string
}

variable "ssh_agent_username" {
  type = string
}

variable "ssh_private_key_path" {
  type = string
}

variable "target_node_name" {
  type = string
}

variable "target_node_ip" {
  type = string
}

variable "target_port" {
  type    = string
  default = "8006"
}
