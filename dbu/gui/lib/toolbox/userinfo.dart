// ignore_for_file: camel_case_types, constant_identifier_names

import './string_extensions.dart';
import './toolbox.dart';

enum LOGIN_TYPE { GENERAL, FACEBOOK, LINE, GOOGLE, INSTAGRAM }

const USERFILE = "user.json";

final ToolBox toolbox = ToolBox.instance;

// User profile and account information
class User {
  int id;
  String email;
  String phone;
  String password;
  String name;
  String city;
  String state;
  String desc;
  String picturl;
  String token = '';
  int logintype = LOGIN_TYPE.GENERAL.index;
  int level = 0;
  int creations = 0;
  int followers = 0;
  int likes = 0;

  User(this.id, this.email, this.phone, this.password, this.name, this.city, this.state, this.desc, this.picturl, this.token,
      this.logintype);

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
        (json['customer_id'] == null) ? 0 : int.parse(json['customer_id']),
        (json['email'] == null) ? "" : json['email'] as String,
        (json['phone'] == null) ? "" : json['phone'] as String,
        (json['password'] == null) ? "" : json['password'] as String,
        (json['name'] == null) ? "" : json['name'] as String,
        (json['city'] == null) ? "" : json['city'] as String,
        (json['state'] == null) ? "" : json['state'] as String,
        (json['desc'] == null) ? "" : json['desc'] as String,
        (json['picturl'] == null) ? "" : json['picturl'] as String,
        (json['token'] == null) ? "" : json['token'] as String,
        (json['loginType'] == null) ? 0 : int.parse(json['loginType']));
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'phone': phone,
        'password': password,
        'name': name,
        'city': city,
        'state': state,
        'desc': desc,
        'picturl': picturl,
        'token': token,
        'login_type': logintype
      };

  // Check whether phone and email are both empty or invalid
  bool checkAccountIsNull() {
    var result = true;
    if (phone.isNotEmpty) {
      result = false;
    } else if (email.isNotEmpty && email.isEmail) {
      result = false;
    }
    return result;
  }

  // Return user ID
  int getId() {
    return id;
  }

  // Set user ID
  void setId(int theId) {
    id = theId;
  }

  String getEmail() {
    return email;
  }

  void setEmail(String theEmail) {
    email = theEmail;
  }

  String getPhone() {
    return phone;
  }

  void setPhone(String thePhone) {
    phone = thePhone;
  }

  String getName() {
    return name;
  }

  void setName(String theName) {
    name = theName;
  }

  String getCity() {
    return city;
  }

  void setCity(String theCity) {
    city = theCity;
  }

  String getState() {
    return state;
  }

  void setState(String theState) {
    state = theState;
  }

  String getDesc() {
    return desc;
  }

  void setDesc(String theDesc) {
    desc = theDesc;
  }

  String getPictUrl() {
    return picturl;
  }

  void setPictUrl(String thePictUrl) {
    picturl = thePictUrl;
  }

  String getToken() {
    return token;
  }

  void setToken(String theToken) {
    token = theToken;
  }

  int getLoginType() {
    return logintype;
  }

  void setLoginType(int type) {
    logintype = type;
  }

  LOGIN_TYPE convType() {
    return LOGIN_TYPE.values[logintype];
  }
}
