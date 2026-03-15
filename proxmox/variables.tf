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

variable "ssh_public_key_path" {
  type    = string
  default = "~/.ssh/id_ed25519.pub"
}

variable "target_node_name" {
  type = string
}

variable "target_node_ip" {
  type = string
}
