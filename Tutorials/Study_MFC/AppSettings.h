#pragma once
#include <string>

template <typename T>
void IncrementSetting(T& setting, int maxValue)
{
	int val = static_cast<int>(setting);
	val = (val + 1) % maxValue;
	setting = static_cast<T>(val);
}

template<typename T>
void DecrementSetting(T& setting, int maxValue)
{
	int val = static_cast<int>(setting);
	val = (val - 1 + maxValue) % maxValue;
	setting = static_cast<T>(val);
}

class DisplayMode
{
public:
	enum Settings{
		Original,
		Smoothed,
		NumSettings
	};
	static const wchar_t IncKey = 'F';
	static const wchar_t DecKey = 'D';
	static Settings Value;
	static std::wstring ToString()
	{
		static const std::wstring Names[NumSettings] =
		{
			L"Original",
			L"Smoothed",
		};

		std::wstring text = L"Mode: ";
		text += Names[Value];
		return text;
	}
	static void Increment()
	{
		IncrementSetting(Value, NumSettings);
	}
	static void Decrement()
	{
		DecrementSetting(Value, NumSettings);
	}
};